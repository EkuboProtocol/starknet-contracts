import { Account, BlockTag, Contract } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.contract_class.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.contract_class.json";
import OwnedNFTContract from "../target/dev/ekubo_OwnedNFT.contract_class.json";
import MockERC20 from "../target/dev/ekubo_MockERC20.contract_class.json";
import Router from "../target/dev/ekubo_Router.contract_class.json";
import { POOL_CASES } from "./cases/pool-cases";
import { SWAP_CASES } from "./cases/swap-cases";
import Decimal from "decimal.js-light";
import { getAmountsForLiquidity } from "./utils/liquidity-to-amounts";
import { setupContracts } from "./utils/setupContracts";
import { deployTokens } from "./utils/deployTokens";
import { fromI129, toI129 } from "./utils/serialize";
import { ACCOUNTS, provider } from "./utils/provider";
import { computeFee } from "./utils/computeFee";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";

Decimal.set({ precision: 80 });

describe("core", () => {
  let setup: Awaited<ReturnType<typeof setupContracts>>;

  beforeAll(async () => {
    setup = await setupContracts({ deployer: ACCOUNTS[0] });
  }, 300_000);

  for (const { name: poolCaseName, pool, positions } of POOL_CASES) {
    describe(poolCaseName, () => {
      let token0: Contract;
      let token1: Contract;
      let account: Account;

      let poolKey: {
        token0: string;
        token1: string;
        fee: bigint;
        tick_spacing: bigint;
        extension: string;
      };

      // set up the pool according to the pool case
      beforeEach(async () => {
        account = ACCOUNTS[0];

        const liquiditiesActual: { token_id: bigint; liquidity: bigint }[] = [];
        const [token0Address, token1Address] = await deployTokens({
          deployer: account,
          classHash: setup.tokenClassHash,
        });

        token0 = new Contract(MockERC20.abi, token0Address, account);
        token1 = new Contract(MockERC20.abi, token1Address, account);

        poolKey = {
          token0: token0Address,
          token1: token1Address,
          fee: pool.fee,
          tick_spacing: pool.tickSpacing,
          extension: "0x0",
        };

        const core = new Contract(
          CoreCompiledContract.abi,
          setup.core,
          account
        );
        const positionsContract = new Contract(
          PositionsCompiledContract.abi,
          setup.positions,
          account
        );
        const nft = new Contract(OwnedNFTContract.abi, setup.nft, account);

        await core.invoke("initialize_pool", [
          poolKey,

          // starting tick
          toI129(pool.startingTick),
        ]);

        for (const { liquidity, bounds } of positions) {
          const { amount0, amount1 } = getAmountsForLiquidity({
            tick: pool.startingTick,
            liquidity,
            bounds,
          });
          await token0.invoke("transfer", [setup.positions, amount0]);
          await token1.invoke("transfer", [setup.positions, amount1]);

          const { transaction_hash } = await positionsContract.invoke(
            "mint_and_deposit",
            [
              poolKey,
              { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
              liquidity,
            ]
          );

          const receipt = await provider.waitForTransaction(transaction_hash, {
            retryInterval: 0,
          });

          const [{ Transfer }] = nft.parseEvents(receipt);

          const parsed = core.parseEvents(receipt);

          const [{ PositionUpdated }] = parsed;

          liquiditiesActual.push({
            token_id: (Transfer as unknown as { token_id: bigint }).token_id,
            liquidity: (
              PositionUpdated as unknown as {
                params: { liquidity_delta: { mag: bigint; sign: boolean } };
              }
            ).params.liquidity_delta.mag,
          });
        }

        // transfer remaining balances to swapper, so it can swap whatever is needed
        await token0.invoke("transfer", [
          setup.router,
          await token0.call("balanceOf", [account.address]),
        ]);
        await token1.invoke("transfer", [
          setup.router,
          await token1.call("balanceOf", [account.address]),
        ]);

        return async () => {
          let cumulativeProtocolFee0 = 0n;
          let cumulativeProtocolFee1 = 0n;

          const withdrawalTransactionHashes: string[] = [];
          for (let i = 0; i < positions.length; i++) {
            const { bounds } = positions[i];

            const boundsArgument = {
              lower: toI129(bounds.lower),
              upper: toI129(bounds.upper),
            };

            const { liquidity: expectedLiquidity, token_id } =
              liquiditiesActual[i];

            const { liquidity, amount0, amount1 } =
              (await positionsContract.call(
                "get_token_info",
                [token_id, poolKey, boundsArgument],
                { blockIdentifier: BlockTag.pending }
              )) as unknown as {
                liquidity: bigint;
                amount0: bigint;
                amount1: bigint;
                fees0: bigint;
                fees1: bigint;
              };

            expect(liquidity).toEqual(expectedLiquidity);

            cumulativeProtocolFee0 += computeFee(amount0, poolKey.fee);
            cumulativeProtocolFee1 += computeFee(amount1, poolKey.fee);

            const { transaction_hash } = await positionsContract.invoke(
              "withdraw",
              [token_id, poolKey, boundsArgument, liquidity, 0, 0, true]
            );
            withdrawalTransactionHashes.push(transaction_hash);
          }

          // wait for all the withdrawals to be mined
          await Promise.all(
            withdrawalTransactionHashes.map((hash) =>
              provider.waitForTransaction(hash, { retryInterval: 0 })
            )
          );

          const [protocolFee0, protocolFee1] = await Promise.all([
            core.call("get_protocol_fees_collected", [token0.address]),
            core.call("get_protocol_fees_collected", [token1.address]),
          ]);

          expect(protocolFee0).toEqual(cumulativeProtocolFee0);
          expect(protocolFee1).toEqual(cumulativeProtocolFee1);

          const [balance0, balance1] = await Promise.all([
            token0.call("balanceOf", [setup.core]),
            token1.call("balanceOf", [setup.core]),
          ]);

          // assuming up to 1 wei of rounding error per swap / withdrawal
          expect(balance0).toBeGreaterThanOrEqual(cumulativeProtocolFee0);
          expect(balance1).toBeGreaterThanOrEqual(cumulativeProtocolFee1);

          // extra is just to account for rounding error for position mints and withdraws as well as swaps (each iteration causes rounding error)
          expect(balance0).toBeLessThanOrEqual(cumulativeProtocolFee0 + 200n);
          expect(balance1).toBeLessThanOrEqual(cumulativeProtocolFee1 + 200n);
        };
      }, 300_000);

      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${swapCase.isToken1 ? "token1" : "token0"}${
          swapCase.skipAhead ? ` skip ${swapCase.skipAhead}` : ""
        }${
          swapCase.sqrtRatioLimit
            ? ` limit ${new Decimal(swapCase.sqrtRatioLimit.toString())
                .div(new Decimal(2).pow(128))
                .toFixed(3)}`
            : ""
        }`, async () => {
          const core = new Contract(
            CoreCompiledContract.abi,
            setup.core,
            account
          );
          const router = new Contract(Router.abi, setup.router, account);

          let transaction_hash: string;
          try {
            ({ transaction_hash } = await router.invoke(
              "swap",
              [
                {
                  pool_key: poolKey,
                  sqrt_ratio_limit: swapCase.sqrtRatioLimit ?? 0,
                  skip_ahead: swapCase.skipAhead ?? 0,
                },
                {
                  amount: toI129(swapCase.amount),
                  token: swapCase.isToken1 ? token1.address : token0.address,
                },
              ],
              {
                maxFee: 1_000_000_000_000_000_000n,
              }
            ));
          } catch (error) {
            transaction_hash = error.transaction_hash;
            if (!transaction_hash) throw error;
          }

          const swap_receipt = await provider.waitForTransaction(
            transaction_hash,
            { retryInterval: 0 }
          );

          switch (swap_receipt.execution_status) {
            case "REVERTED": {
              const revertReason = swap_receipt.revert_reason;

              const hexErrorMessage = /Failure reason: 0x([a-fA-F0-9]+)/g.exec(
                revertReason
              )?.[1];

              expect({
                revert_reason: hexErrorMessage
                  ? Buffer.from(hexErrorMessage, "hex").toString("ascii")
                  : /(RunResources has no remaining steps)/g.exec(
                      revertReason
                    )?.[1] ?? revertReason,
              }).toMatchSnapshot();
              break;
            }
            case "SUCCEEDED": {
              const execution_resources = swap_receipt.execution_resources;
              if ("n_memory_holes" in execution_resources) {
                delete execution_resources["n_memory_holes"];
              }

              const { sqrt_ratio_after, tick_after, liquidity_after, delta } =
                core.parseEvents(swap_receipt)[0].Swapped;

              expect({
                execution_resources,
                delta: {
                  amount0: fromI129((delta as any).amount0),
                  amount1: fromI129((delta as any).amount1),
                },
                liquidity_after,
                sqrt_ratio_after,
                tick_after: fromI129(tick_after as any),
              }).toMatchSnapshot();
              break;
            }
          }
        }, 300_000);
      }
    });
  }
});
