import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import { Account, Contract, hash, Provider } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.sierra.json";
import CoreCompiledContractCASM from "../target/dev/ekubo_Core.casm.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.sierra.json";
import PositionsCompiledContractCASM from "../target/dev/ekubo_Positions.casm.json";
import EnumerableOwnedNFTContract from "../target/dev/ekubo_EnumerableOwnedNFT.sierra.json";
import EnumerableOwnedNFTContractCASM from "../target/dev/ekubo_EnumerableOwnedNFT.casm.json";
import { POOL_CASES } from "./pool-cases";
import { getAccounts } from "./accounts";
import { SWAP_CASES } from "./swap-cases";
import { dump, load } from "./devnet";

describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let accounts: Account[];
  let provider: Provider;

  beforeAll(() => {
    console.log(
      "Starting starknet devnet",
      process.env.STARKNET_SIERRA_COMPILER_PATH
    );

    starknetProcess = spawn("starknet-devnet", [
      "--seed",
      "0",
      ...(process.env.STARKNET_SIERRA_COMPILER_PATH
        ? ["--sierra-compiler-path", process.env.STARKNET_SIERRA_COMPILER_PATH]
        : []),
    ]);

    return new Promise((resolve, reject) => {
      // starknetProcess.stderr.on("data", (data) =>
      //   reject(new Error(data.toString("utf8")))
      // );
      // starknetProcess.stdout.on("data", (data) =>
      //   console.log(data.toString("utf8"))
      // );

      starknetProcess.stdout.on("data", (data) => {
        if (data.toString("utf8").includes("Predeployed UDC")) {
          console.log("Starknet devnet started");
          provider = new Provider({
            sequencer: { baseUrl: "http://127.0.0.1:5050" },
          });
          accounts = getAccounts(provider);
          resolve(null);
        }
      });
    });
  });

  let core: Contract;
  let positions: Contract;

  beforeAll(async () => {
    console.log("Deploying core");
    const coreResponse = await accounts[0].declareAndDeploy(
      {
        contract: CoreCompiledContract as any,
        casm: CoreCompiledContractCASM as any,
      },
      { maxFee: 10000000000000 } // workaround
    );

    console.log(JSON.stringify(coreResponse));

    core = new Contract(
      CoreCompiledContract.abi,
      coreResponse.deploy.address,
      provider
    );

    console.log("Declaring NFTs");

    const declareNftResponse = await accounts[0].declare(
      {
        contract: EnumerableOwnedNFTContract as any,
        casm: EnumerableOwnedNFTContractCASM as any,
      },
      { maxFee: 10000000000000 } // workaround
    );

    console.log(JSON.stringify(declareNftResponse));

    const positionsConstructorCalldata = [
      coreResponse.deploy.address,
      declareNftResponse.class_hash,
      `0x${Buffer.from("https://f.ekubo.org/", "ascii").toString("hex")}`,
    ];
    console.log("Deploying positions", positionsConstructorCalldata);

    const positionsResponse = await accounts[0].declareAndDeploy(
      {
        contract: PositionsCompiledContract as any,
        casm: PositionsCompiledContractCASM as any,
        constructorCalldata: positionsConstructorCalldata,
      },
      { maxFee: 10000000000000 } // workaround
    );

    positions = new Contract(
      PositionsCompiledContract.abi,
      positionsResponse.deploy.address,
      accounts[0]
    );

    await dump();
  });

  beforeEach(async () => {
    await load();
  });

  it("works", async () => {
    const str = await positions.call("token_uri", [1]);
    console.log("token uri of one", str);
  });

  for (const poolCase of POOL_CASES) {
    describe(poolCase.name, () => {
      // set up the pool according to the pool case
      beforeEach(async () => {
        console.log(`Setting up pool for ${poolCase.name}`);
      });

      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${
          swapCase.isToken1 ? "token1" : "token0"
        }`, async () => {
          console.log(`Swap test`);
        });
      }
    });
  }

  afterAll(() => {
    console.log("Shutting down");
    return new Promise((resolve) => {
      starknetProcess.on("close", () => {
        resolve(null);
      });
      starknetProcess.kill();
    });
  });
});
