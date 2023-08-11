import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import { Account, Contract, hash, Provider } from "starknet";
import CoreCompiledContract from "../target/dev/ekubo_Core.sierra.json";
import CoreCompiledContractCASM from "../target/dev/ekubo_Core.casm.json";
import PositionsCompiledContract from "../target/dev/ekubo_Positions.sierra.json";
import PositionsCompiledContractCASM from "../target/dev/ekubo_Positions.casm.json";
import { POOL_CASES } from "./pool-cases";
import { getAccounts } from "./accounts";

describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let accounts: Account[];
  let provider: Provider;

  beforeAll(() => {
    console.log("Starting starknet devnet");
    starknetProcess = spawn("starknet-devnet", ["--seed", "0"]);

    return new Promise((resolve) => {
      // starknetProcess.stderr.on("data", (data) =>
      //   console.error(data.toString("utf8"))
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

  beforeEach(async () => {
    console.log("Deploying core");
    const response = await accounts[0].declareAndDeploy(
      {
        contract: CoreCompiledContract as any,
        casm: CoreCompiledContractCASM as any,
      },
      { maxFee: 10000000000000 } // workaround
    );

    console.log(response);
  });

  // beforeEach(async () => {
  //   console.log("Deploying positions with core address", core.address);
  //   positions = await positionsContractFactory.deploy(
  //     core.address,
  //     "https://f.ekubo.org/"
  //   );
  // });

  it("works", () => {
    console.log("test body");
  });

  for (const poolCase of POOL_CASES) {
    describe(poolCase.name, () => {
      // // set up the pool according to the pool case
      // beforeEach(async () => {
      //   console.log("Setting up pool");
      // });
      // then test swap for each swap case
      // for (const swapCase of SWAP_CASES) {
      //   it(`swap ${swapCase.amount} ${
      //     swapCase.isToken1 ? "token1" : "token0"
      //   }`, async () => {
      //     expect("result").toMatchSnapshot();
      //   });
      // }
    });
  }

  afterAll(async () => {
    console.log("Shutting down");
    await new Promise((resolve) => {
      starknetProcess.on("close", () => {
        resolve(null);
      });
      starknetProcess.kill();
    });
  });
});
