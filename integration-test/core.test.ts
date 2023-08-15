import { ChildProcessWithoutNullStreams } from "child_process";

import { Account, Contract, Provider } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.sierra.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.sierra.json";
import EnumerableOwnedNFTContract from "../target/dev/ekubo_EnumerableOwnedNFT.sierra.json";
import SimpleERC20 from "../target/dev/ekubo_SimpleERC20.sierra.json";
import { POOL_CASES } from "./pool-cases";
import { SWAP_CASES } from "./swap-cases";
import { dumpState, loadDump, startDevnet } from "./devnet";

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

  const ADDRESSES = {
    token0: "0x1329afe083102885daaa3dc0bbbefa65b5e04f3130e0a5c4b713b42dd35562a",
    token1: "0x618d100c061d201fbb64bde289b8316b6696ddb31299db5808d53cfef8990f2",
    coreAddress:
      "0x3f6fe8574ebf90ebd0ba09d8d952a410543415097999202ae3918188ab967cb",
    positionsAddress:
      "0x47bf18efb3ea4dd07887457a118fd8f84b0afb582a5761a2d09355c88e10386",
    nftAddress:
      "0x5001bdab48ad23f4eed385363afb3e6d95b2bea4a69c342dd66cca057c9e543",
  };

  beforeAll(async () => {
    [starknetProcess, killedPromise, provider, accounts] = await startDevnet();
    await loadDump();
    token0 = new Contract(SimpleERC20.abi, ADDRESSES.token0, accounts[0]);
    token1 = new Contract(SimpleERC20.abi, ADDRESSES.token1, accounts[0]);

    core = new Contract(
      CoreCompiledContract.abi,
      ADDRESSES.coreAddress,
      accounts[0]
    );

    positions = new Contract(
      PositionsCompiledContract.abi,
      ADDRESSES.positionsAddress,
      accounts[0]
    );

    nft = new Contract(
      EnumerableOwnedNFTContract.abi,
      ADDRESSES.nftAddress,
      accounts[0]
    );
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

        await dumpState("dumppool.bin");
      });

      beforeEach(async () => {
        await loadDump("dumppool.bin");
      });

      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${
          swapCase.isToken1 ? "token1" : "token0"
        }`, async () => {
          console.log(`Swap test`);
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
