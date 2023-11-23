import { Account, Contract, TransactionStatus } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.contract_class.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.contract_class.json";
import OwnedNFTContract from "../target/dev/ekubo_OwnedNFT.contract_class.json";
import SimpleERC20 from "../target/dev/ekubo_SimpleERC20.contract_class.json";
import SimpleSwapper from "../target/dev/ekubo_SimpleSwapper.contract_class.json";
import { POOL_CASES } from "./pool-cases";
import { SWAP_CASES } from "./swap-cases";
import { DevnetProvider } from "./devnet";
import { MAX_SQRT_RATIO, MIN_SQRT_RATIO } from "./constants";
import ADDRESSES from "./addresses.json";
import Decimal from "decimal.js-light";
import { getAccounts } from "./accounts";
import { getAmountsForLiquidity } from "./liquidity-to-amounts";

function toI129(x: bigint): { mag: bigint; sign: "0x1" | "0x0" } {
  return {
    mag: x < 0n ? x * -1n : x,
    sign: x < 0n ? "0x1" : "0x0",
  };
}

function fromI129(x: { mag: bigint; sign: boolean }): bigint {
  return x.sign ? x.mag * -1n : x.mag;
}

Decimal.set({ precision: 80 });

function computeFee(x: bigint, fee: bigint): bigint {
  const p = x * fee;
  return p / 2n ** 128n + (p % 2n ** 128n !== 0n ? 1n : 0n);
}
describe("core", () => {
  let provider: DevnetProvider;
  let accounts: Account[];

  let core: Contract;
  let positionsContract: Contract;
  let nft: Contract;
  let token0: Contract;
  let token1: Contract;
  let swapper: Contract;

  beforeAll(async () => {
    provider = new DevnetProvider();
    accounts = getAccounts(provider);

    await provider.loadDump();
    token0 = new Contract(SimpleERC20.abi, ADDRESSES.token0, accounts[0]);
    token1 = new Contract(SimpleERC20.abi, ADDRESSES.token1, accounts[0]);

    core = new Contract(CoreCompiledContract.abi, ADDRESSES.core, accounts[0]);

    positionsContract = new Contract(
      PositionsCompiledContract.abi,
      ADDRESSES.positions,
      accounts[0]
    );

    nft = new Contract(
      OwnedNFTContract.abi,
      ADDRESSES.nft,
      accounts[0]
    );

    swapper = new Contract(SimpleSwapper.abi, ADDRESSES.swapper, accounts[0]);
  });

  for (const {
    only: poolCaseOnly,
    name: poolCaseName,
    pool,
    positions: positions,
  } of POOL_CASES) {
    (poolCaseOnly ? describe.only : describe)(poolCaseName, () => {
      let poolKey: {
        token0: string;
        token1: string;
        fee: bigint;
        tick_spacing: bigint;
        extension: string;
      };

      const liquiditiesActual: bigint[] = [];

      let setupSuccess = false;

      // set up the pool according to the pool case
      beforeAll(async () => {
        await provider.loadDump();

        poolKey = {
          token0: token0.address,
          token1: token1.address,
          fee: pool.fee,
          tick_spacing: pool.tickSpacing,
          extension: "0x0",
        };

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
          await token0.invoke("transfer", [
            positionsContract.address, // recipient
            amount0, // amount
          ]);
          await token1.invoke("transfer", [
            positionsContract.address, // recipient
            amount1, // amount
          ]);

          const { transaction_hash } = await positionsContract.invoke(
            "mint_and_deposit",
            [
              poolKey,
              { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
              liquidity,
            ]
          );

          const receipt = await provider.getTransactionReceipt(
            transaction_hash
          );

          const parsed = positionsContract.parseEvents(receipt);

          const [{ PositionMinted }, { Deposit }] = parsed;

          liquiditiesActual.push(Deposit.liquidity as bigint);
        }

        // transfer remaining balances to swapper, so it can swap whatever is needed
        await token0.invoke("transfer", [
          swapper.address,
          await token0.call("balanceOf", [accounts[0].address]),
        ]);
        await token1.invoke("transfer", [
          swapper.address,
          await token1.call("balanceOf", [accounts[0].address]),
        ]);

        await provider.dumpState("dump-pool.bin");

        setupSuccess = true;
      });

      beforeEach(async () => {
        if (setupSuccess) {
          await provider.loadDump("dump-pool.bin");
        }
      });

      afterEach(async () => {
        if (setupSuccess) {
          let cumulativeProtocolFee0 = 0n;
          let cumulativeProtocolFee1 = 0n;

          for (let i = 0; i < positions.length; i++) {
            const { bounds } = positions[i];

            const boundsArgument = {
              lower: toI129(bounds.lower),
              upper: toI129(bounds.upper),
            };

            const { liquidity, amount0, amount1 } =
              (await positionsContract.call("get_token_info", [
                i + 1,
                poolKey,
                boundsArgument,
              ])) as unknown as {
                liquidity: bigint;
                amount0: bigint;
                amount1: bigint;
                fees0: bigint;
                fees1: bigint;
              };

            expect(liquidity).toEqual(liquiditiesActual[i]);

            cumulativeProtocolFee0 += computeFee(amount0, poolKey.fee);
            cumulativeProtocolFee1 += computeFee(amount1, poolKey.fee);

            await positionsContract.invoke("withdraw", [
              i + 1,
              poolKey,
              boundsArgument,
              liquiditiesActual[i],
              0,
              0,
              true,
            ]);
          }

          const [protocolFee0, protocolFee1] = await Promise.all([
            core.call("get_protocol_fees_collected", [token0.address]),
            core.call("get_protocol_fees_collected", [token1.address]),
          ]);

          expect(protocolFee0).toEqual(cumulativeProtocolFee0);
          expect(protocolFee1).toEqual(cumulativeProtocolFee1);

          const [balance0, balance1] = await Promise.all([
            token0.call("balanceOf", [core.address]),
            token1.call("balanceOf", [core.address]),
          ]);

          // assuming up to 1 wei of rounding error per swap / withdrawal
          expect(balance0).toBeGreaterThanOrEqual(cumulativeProtocolFee0);
          expect(balance1).toBeGreaterThanOrEqual(cumulativeProtocolFee1);

          // 100 is just to account for rounding error for position mints and withdraws as well as swaps (each iteration causes rounding error)
          expect(balance0).toBeLessThanOrEqual(cumulativeProtocolFee0 + 200n);
          expect(balance1).toBeLessThanOrEqual(cumulativeProtocolFee1 + 200n);
        }
      });

      const RECIPIENT = "0xabcd";

      for (const swapCase of SWAP_CASES) {
        (swapCase.only ? it.only : it)(
          `swap ${swapCase.amount} ${swapCase.isToken1 ? "token1" : "token0"}${swapCase.skipAhead ? ` skip ${swapCase.skipAhead}` : ""
          }${swapCase.sqrtRatioLimit
            ? ` limit ${new Decimal(swapCase.sqrtRatioLimit.toString())
              .div(new Decimal(2).pow(128))
              .toFixed(3)}`
            : ""
          }`,
          async () => {
            let transaction_hash: string;
            try {
              ({ transaction_hash } = await swapper.invoke(
                "swap",
                [
                  poolKey,
                  {
                    amount: toI129(swapCase.amount),
                    is_token1: swapCase.isToken1,
                    sqrt_ratio_limit:
                      swapCase.sqrtRatioLimit ??
                      (swapCase.isToken1 != swapCase.amount < 0
                        ? MAX_SQRT_RATIO
                        : MIN_SQRT_RATIO),
                    skip_ahead: swapCase.skipAhead ?? 0,
                  },
                  RECIPIENT,
                  swapCase.amountLimit ??
                  (swapCase.amount < 0 ? 2n ** 128n - 1n : 0n),
                ],
                {
                  maxFee: 1_000_000_000_000_000n,
                }
              ));
            } catch (error) {
              transaction_hash = error.transaction_hash;
              if (!transaction_hash) throw error;
            }

            const swap_receipt = await provider.getTransactionReceipt(
              transaction_hash
            );

            switch (swap_receipt.status) {
              case TransactionStatus.REVERTED: {
                const revertReason = (swap_receipt as any)
                  .revert_reason as string;

                const hexErrorMessage =
                  /Execution was reverted; failure reason: \[0x([a-fA-F0-9]+)]\./g.exec(
                    revertReason
                  )?.[1];

                expect({
                  revert_reason: hexErrorMessage
                    ? Buffer.from(hexErrorMessage, "hex").toString("ascii")
                    : /(End of program was not reached)/g.exec(
                      revertReason
                    )?.[1] ?? "could not parse error",
                }).toMatchSnapshot();
                break;
              }
              case TransactionStatus.ACCEPTED_ON_L2: {
                const execution_resources = (swap_receipt as any)
                  .execution_resources;
                if (execution_resources) {
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
          }
        );
      }
    });
  }
});
