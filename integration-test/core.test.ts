import { ChildProcessWithoutNullStreams } from "child_process";

import { Account, Contract, Provider, TransactionStatus } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.sierra.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.sierra.json";
import EnumerableOwnedNFTContract from "../target/dev/ekubo_EnumerableOwnedNFT.sierra.json";
import SimpleERC20 from "../target/dev/ekubo_SimpleERC20.sierra.json";
import SimpleSwapper from "../target/dev/ekubo_SimpleSwapper.sierra.json";
import { POOL_CASES } from "./pool-cases";
import { SWAP_CASES } from "./swap-cases";
import { dumpState, loadDump, startDevnet } from "./devnet";
import { MAX_SQRT_RATIO, MIN_SQRT_RATIO } from "./constants";
import ADDRESSES from "./addresses.json";
import Decimal from "decimal.js-light";

function toI129(x: bigint): { mag: bigint; sign: "0x1" | "0x0" } {
  return {
    mag: x < 0n ? x * -1n : x,
    sign: x < 0n ? "0x1" : "0x0",
  };
}

function amount0Delta({
  liquidity,
  sqrtRatioLower,
  sqrtRatioUpper,
}: {
  liquidity: bigint;
  sqrtRatioLower: bigint;
  sqrtRatioUpper: bigint;
}) {
  const numerator = (liquidity << 128n) * (sqrtRatioUpper - sqrtRatioLower);

  const divOne =
    numerator / sqrtRatioUpper + (numerator % sqrtRatioUpper === 0n ? 0n : 1n);

  return divOne / sqrtRatioLower + (divOne % sqrtRatioLower === 0n ? 0n : 1n);
}

function amount1Delta({
  liquidity,
  sqrtRatioLower,
  sqrtRatioUpper,
}: {
  liquidity: bigint;
  sqrtRatioLower: bigint;
  sqrtRatioUpper: bigint;
}) {
  const numerator = liquidity * (sqrtRatioUpper - sqrtRatioLower);
  const result =
    (numerator % (1n << 128n) !== 0n ? 1n : 0n) + numerator / (1n << 128n);
  return result;
}

Decimal.set({ precision: 80 });
function tickToSqrtRatio(tick: bigint) {
  return BigInt(
    new Decimal("1.000001")
      .pow(new Decimal(Number(tick)))
      .mul(new Decimal(2).pow(128))
      .toFixed(0)
  );
}

function getAmountsForLiquidity({
  bounds,
  liquidity,
  tick,
}: {
  bounds: { lower: bigint; upper: bigint };
  liquidity: bigint;
  tick: bigint;
}): { amount0: bigint; amount1: bigint } {
  if (tick < bounds.lower) {
    return {
      amount0: amount0Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
      amount1: 0n,
    };
  } else if (tick < bounds.upper) {
    return {
      amount0: amount0Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(tick),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
      amount1: amount1Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(tick),
      }),
    };
  } else {
    return {
      amount0: 0n,
      amount1: amount1Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
    };
  }
}

describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let accounts: Account[];
  let provider: Provider;
  let killedPromise: Promise<null>;

  let core: Contract;
  let positionsContract: Contract;
  let nft: Contract;
  let token0: Contract;
  let token1: Contract;
  let swapper: Contract;

  beforeAll(async () => {
    [starknetProcess, killedPromise, provider, accounts] = await startDevnet();
    await loadDump();
    token0 = new Contract(SimpleERC20.abi, ADDRESSES.token0, accounts[0]);
    token1 = new Contract(SimpleERC20.abi, ADDRESSES.token1, accounts[0]);

    core = new Contract(CoreCompiledContract.abi, ADDRESSES.core, accounts[0]);

    positionsContract = new Contract(
      PositionsCompiledContract.abi,
      ADDRESSES.positions,
      accounts[0]
    );

    nft = new Contract(
      EnumerableOwnedNFTContract.abi,
      ADDRESSES.nft,
      accounts[0]
    );

    swapper = new Contract(SimpleSwapper.abi, ADDRESSES.swapper, accounts[0]);
  });

  for (const { name: poolCaseName, pool, positions: positions } of POOL_CASES) {
    describe(poolCaseName, () => {
      let poolKey: {
        token0: string;
        token1: string;
        fee: bigint;
        tick_spacing: bigint;
        extension: string;
      };

      // set up the pool according to the pool case
      beforeAll(async () => {
        await loadDump();

        console.log(`Setting up pool for ${poolCaseName}`);

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

          console.log("Parsed events", parsed);

          const [{ PositionMinted }, { Deposit }] = parsed;

          if (Deposit.liquidity !== liquidity) {
            throw new Error(
              `Liquidity not equal: ${Deposit.liquidity} !== ${liquidity}`
            );
          }
        }

        await dumpState("dump-pool.bin");
      });

      beforeEach(async () => {
        await loadDump("dump-pool.bin");
      });

      afterEach(async () => {
        for (let i = 0; i < positions.length; i++) {
          const { bounds, liquidity } = positions[i];
          await positionsContract.invoke("withdraw", [
            i + 1,
            poolKey,
            { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
            liquidity,
            0,
            0,
            true,
          ]);
        }
      });

      const RECIPIENT = "0xabcd";

      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${
          swapCase.isToken1 ? "token1" : "token0"
        }`, async () => {
          console.log("Testing swap");

          let transaction_hash: string;
          try {
            ({ transaction_hash } = await swapper.invoke("swap", [
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
            ]));
          } catch (error) {
            transaction_hash = error.transaction_hash;
            if (!transaction_hash) throw error;
          }

          const swap_receipt = await provider.getTransactionReceipt(
            transaction_hash
          );

          console.log(swap_receipt);

          switch (swap_receipt.status) {
            case TransactionStatus.REJECTED:
              break;
            case TransactionStatus.ACCEPTED_ON_L2:
              expect(
                (swap_receipt as any).execution_resources
              ).toMatchSnapshot();
              console.log(swap_receipt);
              console.log(core.parseEvents(swap_receipt));
              break;
          }
        });
      }
    });
  }

  afterAll(async () => {
    starknetProcess.kill();
    await killedPromise;
  });
});
