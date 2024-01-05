import {
  Account,
  Contract,
  Nonce,
  num,
  RpcProvider,
  shortString,
} from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.contract_class.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.contract_class.json";
import OwnedNFTContract from "../target/dev/ekubo_OwnedNFT.contract_class.json";
import SimpleERC20 from "../target/dev/ekubo_SimpleERC20.contract_class.json";
import Router from "../target/dev/ekubo_Router.contract_class.json";
import { POOL_CASES } from "./pool-cases";
import { SWAP_CASES } from "./swap-cases";
import Decimal from "decimal.js-light";
import { getAmountsForLiquidity } from "./liquidity-to-amounts";
import CoreCompiledContractCASM from "../target/dev/ekubo_Core.compiled_contract_class.json";
import PositionsCompiledContractCASM from "../target/dev/ekubo_Positions.compiled_contract_class.json";
import OwnedNFTContractCASM from "../target/dev/ekubo_OwnedNFT.compiled_contract_class.json";
import SimpleERC20CASM from "../target/dev/ekubo_SimpleERC20.compiled_contract_class.json";
import RouterCASM from "../target/dev/ekubo_Router.compiled_contract_class.json";

export async function setupContracts({
  getAndIncrementNonce,
  deployer,
}: {
  deployer: Account;
  getAndIncrementNonce: () => Nonce;
}) {
  const simpleTokenContractDeclare = await deployer.declare(
    {
      contract: SimpleERC20 as any,
      casm: SimpleERC20CASM as any,
    },
    { nonce: getAndIncrementNonce() }
  );

  const coreContractDeclare = await deployer.declare(
    {
      contract: CoreCompiledContract as any,
      casm: CoreCompiledContractCASM as any,
    },
    { nonce: getAndIncrementNonce() }
  );

  const coreDeploy = await deployer.deploy(
    {
      classHash: coreContractDeclare.class_hash,
    },
    {
      nonce: getAndIncrementNonce(),
    }
  );

  const declareNftResponse = await deployer.declare(
    {
      contract: OwnedNFTContract as any,
      casm: OwnedNFTContractCASM as any,
    },
    { nonce: getAndIncrementNonce() }
  );

  const positionsConstructorCalldata = [
    coreDeploy.contract_address[0],
    declareNftResponse.class_hash,
    shortString.encodeShortString("https://f.ekubo.org/"),
  ];

  const positionsDeclare = await deployer.declare(
    {
      contract: PositionsCompiledContract as any,
      casm: PositionsCompiledContractCASM as any,
    },
    { nonce: getAndIncrementNonce() }
  );

  const positionsDeploy = await deployer.deploy(
    {
      classHash: positionsDeclare.class_hash,
      constructorCalldata: positionsConstructorCalldata,
    },
    { nonce: getAndIncrementNonce() }
  );

  const positions = new Contract(
    PositionsCompiledContract.abi,
    positionsDeploy.contract_address[0],
    deployer
  );

  const routerDeclare = await deployer.declare(
    {
      contract: Router as any,
      casm: RouterCASM as any,
    },
    { nonce: getAndIncrementNonce() }
  );

  const routerDeploy = await deployer.deploy(
    {
      classHash: routerDeclare.class_hash,
      constructorCalldata: [coreDeploy.contract_address[0]],
    },
    { nonce: getAndIncrementNonce() }
  );

  const nftAddress = (await positions.call("get_nft_address")) as bigint;

  return {
    core: coreDeploy.contract_address[0],
    positions: positionsDeploy.contract_address[0],
    router: routerDeploy.contract_address[0],
    nft: num.toHexString(nftAddress),
    tokenClassHash: simpleTokenContractDeclare.class_hash,
  };
}

export async function deployTokens({
  classHash,
  deployer,
  getAndIncrementNonce,
}: {
  deployer: Account;
  classHash: string;
  getAndIncrementNonce: () => Nonce;
}): Promise<[token0: string, token1: string]> {
  const {
    contract_address: [tokenAddressA],
  } = await deployer.deploy(
    {
      classHash: classHash,

      constructorCalldata: [deployer.address],
    },
    { nonce: getAndIncrementNonce() }
  );

  const {
    contract_address: [tokenAddressB],
  } = await deployer.deploy(
    {
      classHash: classHash,
      constructorCalldata: [deployer.address],
    },
    { nonce: getAndIncrementNonce() }
  );

  const [token0, token1] =
    BigInt(tokenAddressA) < BigInt(tokenAddressB)
      ? [tokenAddressA, tokenAddressB]
      : [tokenAddressB, tokenAddressA];

  return [token0, token1];
}

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
  let provider: RpcProvider;
  let deployer: Account;
  let nonce: Nonce;

  const getAndIncrementNonce = (): Nonce => {
    let result: Nonce = nonce;
    nonce = num.toHexString(BigInt(nonce) + 1n);
    return result;
  };

  let core: Contract;
  let positionsContract: Contract;
  let nft: Contract;
  let router: Contract;

  let tokenClassHash: string;

  beforeAll(async () => {
    provider = new RpcProvider({
      nodeUrl: "http://127.0.0.1:5050",
    });

    deployer = new Account(
      provider,
      "0x517ececd29116499f4a1b64b094da79ba08dfd54a3edaa316134c41f8160973",
      "0x1800000000300000180000000000030000000000003006001800006600"
    );

    nonce = await deployer.getNonce("pending");

    const setup = await setupContracts({ deployer, getAndIncrementNonce });

    core = new Contract(CoreCompiledContract.abi, setup.core, deployer);
    positionsContract = new Contract(
      PositionsCompiledContract.abi,
      setup.positions,
      deployer
    );
    nft = new Contract(OwnedNFTContract.abi, setup.nft, deployer);
    router = new Contract(Router.abi, setup.router, deployer);

    tokenClassHash = setup.tokenClassHash;
  });

  const anyPoolCasesOnly = POOL_CASES.some((p) => p.only);

  for (const {
    only: poolCaseOnly,
    name: poolCaseName,
    pool,
    positions: positions,
  } of POOL_CASES) {
    (poolCaseOnly ? describe.only : describe)(poolCaseName, () => {
      let token0: Contract;
      let token1: Contract;

      let poolKey: {
        token0: string;
        token1: string;
        fee: bigint;
        tick_spacing: bigint;
        extension: string;
      };

      const liquiditiesActual: bigint[] = [];

      // set up the pool according to the pool case
      beforeEach(async () => {
        const [token0Address, token1Address] = await deployTokens({
          deployer,
          classHash: tokenClassHash,
          getAndIncrementNonce,
        });

        token0 = new Contract(SimpleERC20.abi, token0Address, deployer);
        token1 = new Contract(SimpleERC20.abi, token1Address, deployer);

        poolKey = {
          token0: token0Address,
          token1: token1Address,
          fee: pool.fee,
          tick_spacing: pool.tickSpacing,
          extension: "0x0",
        };

        await core.invoke(
          "initialize_pool",
          [
            poolKey,

            // starting tick
            toI129(pool.startingTick),
          ],
          { nonce: getAndIncrementNonce() }
        );

        for (const { liquidity, bounds } of positions) {
          const { amount0, amount1 } = getAmountsForLiquidity({
            tick: pool.startingTick,
            liquidity,
            bounds,
          });
          await token0.invoke(
            "transfer",
            [positionsContract.address, amount0],
            { nonce: getAndIncrementNonce() }
          );
          await token1.invoke(
            "transfer",
            [positionsContract.address, amount1],
            { nonce: getAndIncrementNonce() }
          );

          const { transaction_hash } = await positionsContract.invoke(
            "mint_and_deposit",
            [
              poolKey,
              { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
              liquidity,
            ],
            { nonce: getAndIncrementNonce() }
          );

          const receipt = await provider.waitForTransaction(transaction_hash, {
            retryInterval: 0,
          });

          const parsed = positionsContract.parseEvents(receipt);

          const [{ PositionMinted }, { Deposit }] = parsed;

          liquiditiesActual.push(Deposit.liquidity as bigint);
        }

        // transfer remaining balances to swapper, so it can swap whatever is needed
        await token0.invoke(
          "transfer",
          [router.address, await token0.call("balanceOf", [deployer.address])],
          { nonce: getAndIncrementNonce() }
        );
        await token1.invoke(
          "transfer",
          [router.address, await token1.call("balanceOf", [deployer.address])],
          { nonce: getAndIncrementNonce() }
        );
      });

      for (const swapCase of SWAP_CASES) {
        (swapCase.only && (!anyPoolCasesOnly || poolCaseOnly) ? it.only : it)(
          `swap ${swapCase.amount} ${swapCase.isToken1 ? "token1" : "token0"}${
            swapCase.skipAhead ? ` skip ${swapCase.skipAhead}` : ""
          }${
            swapCase.sqrtRatioLimit
              ? ` limit ${new Decimal(swapCase.sqrtRatioLimit.toString())
                  .div(new Decimal(2).pow(128))
                  .toFixed(3)}`
              : ""
          }`,
          async () => {
            let transaction_hash: string;
            try {
              ({ transaction_hash } = await router.invoke(
                "raw_swap",
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
                  maxFee: 1_000_000_000_000_000n,
                  nonce: getAndIncrementNonce(),
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

                const hexErrorMessage =
                  /Failure reason: 0x([a-fA-F0-9]+)/g.exec(revertReason)?.[1];

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
          }
        );
      }

      afterEach(async () => {
        let cumulativeProtocolFee0 = 0n;
        let cumulativeProtocolFee1 = 0n;

        const withdrawalTransactionHashes: string[] = [];
        for (let i = 0; i < positions.length; i++) {
          const { bounds } = positions[i];

          const boundsArgument = {
            lower: toI129(bounds.lower),
            upper: toI129(bounds.upper),
          };

          const { liquidity, amount0, amount1 } = (await positionsContract.call(
            "get_token_info",
            [i + 1, poolKey, boundsArgument],
            { blockIdentifier: "pending" }
          )) as unknown as {
            liquidity: bigint;
            amount0: bigint;
            amount1: bigint;
            fees0: bigint;
            fees1: bigint;
          };

          expect(liquidity).toEqual(liquiditiesActual[i]);

          cumulativeProtocolFee0 += computeFee(amount0, poolKey.fee);
          cumulativeProtocolFee1 += computeFee(amount1, poolKey.fee);

          const { transaction_hash } = await positionsContract.invoke(
            "withdraw",
            [i + 1, poolKey, boundsArgument, liquiditiesActual[i], 0, 0, true],
            { nonce: getAndIncrementNonce() }
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
          token0.call("balanceOf", [core.address]),
          token1.call("balanceOf", [core.address]),
        ]);

        // assuming up to 1 wei of rounding error per swap / withdrawal
        expect(balance0).toBeGreaterThanOrEqual(cumulativeProtocolFee0);
        expect(balance1).toBeGreaterThanOrEqual(cumulativeProtocolFee1);

        // 100 is just to account for rounding error for position mints and withdraws as well as swaps (each iteration causes rounding error)
        expect(balance0).toBeLessThanOrEqual(cumulativeProtocolFee0 + 200n);
        expect(balance1).toBeLessThanOrEqual(cumulativeProtocolFee1 + 200n);
      });
    });
  }
});
