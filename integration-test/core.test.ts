import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import { Account, RpcProvider, Contract, ContractFactory } from "starknet";

describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let rpcUrl: string;
  let accounts: Account[];
  let provider: RpcProvider;

  beforeAll(() => {
    starknetProcess = spawn("katana", ["--seed", "0"]);

    return new Promise((resolve) => {
      starknetProcess.stdout.once("data", (data) => {
        let str = data.toString("utf8");

        rpcUrl = /(http:\/\/[\w\.:\d]+)/g
          .exec(str)?.[1]
          ?.replace(/0\.0\.0\.0/, "127.0.0.1");

        provider = new RpcProvider({
          nodeUrl: rpcUrl,
        });

        accounts = [
          ...str.matchAll(
            /\|\s+Account Address\s+\|\s+(0x[a-f0-9]+)\s+\|\s+Private key\s+\|\s+(0x[a-f0-9]+)\s+\|\s+Public key\s+\|\s+(0x[a-f0-9]+)/gi
          ),
        ]
          .map((match) => ({
            address: match[1],
            privateKey: match[2],
            publicKey: match[3],
          }))
          .map(
            ({ address, privateKey }) =>
              new Account(provider, address, privateKey)
          );

        resolve(null);
      });
    });
  });

  let factory: ContractFactory;
  let core: Contract;

  beforeEach(async () => {
    factory = new ContractFactory({}, contract_address, accounts[0]);
    core = await factory.deploy();
  });

  it("works", () => {});

  afterAll(async () => {
    console.log("killing devnet");

    return new Promise((resolve) => {
      starknetProcess.on("close", () => {
        console.log("closed");
        resolve(null);
      });
      starknetProcess.kill();
    });
  });
});
