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

function toI129(x: bigint): { mag: bigint; sign: "0x1" | "0x0" } {
  return {
    mag: x < 0n ? x * -1n : x,
    sign: x < 0n ? "0x1" : "0x0",
  };
}
describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let accounts: Account[];
  let provider: Provider;
  let killedPromise: Promise<null>;

  let core: Contract;
  let positions: Contract;
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

    positions = new Contract(
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

  for (const {
    name: poolCaseName,
    pool: poolParams,
    positions: poolCasePositions,
  } of POOL_CASES) {
    describe(poolCaseName, () => {
      const positionsToWithdraw: { id: bigint; liquidity: bigint }[] = [];
      let poolKey;

      // set up the pool according to the pool case
      beforeAll(async () => {
        await loadDump();

        console.log(`Setting up pool for ${poolCaseName}`);

        poolKey = {
          token0: token0.address,
          token1: token1.address,
          fee: poolParams.fee,
          tick_spacing: poolParams.tickSpacing,
          extension: "0x0",
        };

        await core.invoke("initialize_pool", [
          poolKey,

          // starting tick
          toI129(poolParams.startingTick),
        ]);

        for (const { liquidity, bounds } of poolCasePositions) {
          await token0.invoke("transfer", [
            positions.address, // recipient
            1000, // amount
          ]);
          await token1.invoke("transfer", [
            positions.address, // recipient
            1000, // amount
          ]);

          const { transaction_hash } = await positions.invoke(
            "mint_and_deposit",
            [
              poolKey,
              { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
              0,
            ]
          );

          const receipt = await provider.getTransactionReceipt(
            transaction_hash
          );
          const [
            { PositionMinted: positionMintedEvent },
            { Deposit: depositEvent },
          ] = positions.parseEvents(receipt);
          const [{ Transfer: transferEvent }] = nft.parseEvents(receipt);
          positionsToWithdraw.push({
            id: transferEvent.token_id as any,
            liquidity: depositEvent.liquidity as any,
          });
        }

        await dumpState("dump-pool.bin");
      });

      beforeEach(async () => {
        await loadDump("dump-pool.bin");
      });

      const RECIPIENT = "0xabcd";

      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${
          swapCase.isToken1 ? "token1" : "token0"
        }`, async () => {
          console.log("Testing swap");

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
                    swapCase.priceLimit ??
                    (swapCase.isToken1 != swapCase.amount < 0
                      ? MAX_SQRT_RATIO
                      : MIN_SQRT_RATIO),
                  skip_ahead: swapCase.skipAhead ?? 0,
                },
                RECIPIENT,
              ],
              { maxFee: 250n * 1_000_000_000n } // 250 gwei
            ));
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
              console.log(swap_receipt);
              console.log(core.parseEvents(swap_receipt));
              break;
          }
        });
      }

      afterEach(async () => {
        for (let i = 0; i < poolCasePositions.length; i++) {
          const { bounds } = poolCasePositions[i];
          await positions.invoke("withdraw", [
            positionsToWithdraw[i].id,
            poolKey,
            { lower: toI129(bounds.lower), upper: toI129(bounds.upper) },
            positionsToWithdraw[i].liquidity,
            0,
            0,
            true,
          ]);
        }
      });
    });
  }

  afterAll(async () => {
    starknetProcess.kill();
    await killedPromise;
  });
});
