import { ChildProcessWithoutNullStreams, spawn } from "child_process";

import {
  Account,
  RpcProvider,
  Contract,
  ContractFactory,
  CompiledContract,
  hash,
} from "starknet";
import CoreCompiledContract from "../out/core.json";
import CoreCasmCompiledContract from "../out/core.casm.json";
import QuoterCompiledContract from "../out/quoter.json";
import PositionsCompiledContract from "../out/positions.json";

function numberToFixedPoint128(x: number): bigint {
  let power = 0;
  while (x % 1 !== 0) {
    power++;
    x *= 10;
  }

  return (BigInt(x) * 2n ** 128n) / 10n ** BigInt(power);
}

const MAX_TICK_SPACING = 693148;
const MAX_TICK = 88722883;
const MIN_TICK = -88722883;

const POOL_CASES: Array<{
  name: string;
  pool: {
    starting_price: number;
    tick_spacing: number;
    fee: number;
  };
  positions: {
    bounds: {
      lower: number;
      upper: number;
    };
    liquidity: bigint;
  }[];
}> = [
  {
    name: "no liquidity, starting at price 1, tick_spacing==1, fee=0.003",
    pool: { starting_price: 1, tick_spacing: 1, fee: 0.003 },
    positions: [],
  },
  {
    name: "single position, full range liquidity, starting at price 1",
    pool: {
      starting_price: 1,
      tick_spacing: 1,
      fee: 0.003,
    },
    positions: [
      { bounds: { lower: MIN_TICK, upper: MAX_TICK }, liquidity: 10000n },
    ],
  },
];

const MAX_U128 = 2n ** 128n - 1n;

const SWAP_CASES: Array<{
  amount: bigint;
  isToken1: boolean;
  priceLimit?: bigint;
  skipAhead?: number;
}> = [
  {
    amount: 10000n,
    isToken1: true,
  },
  {
    amount: 10000n,
    isToken1: false,
  },
  {
    amount: -10000n,
    isToken1: true,
  },
  {
    amount: -10000n,
    isToken1: false,
  },
  {
    amount: MAX_U128,
    isToken1: true,
  },
  {
    amount: MAX_U128,
    isToken1: false,
  },
  {
    amount: -MAX_U128,
    isToken1: true,
  },
  {
    amount: -MAX_U128,
    isToken1: false,
  },
];

describe("core tests", () => {
  let starknetProcess: ChildProcessWithoutNullStreams;
  let rpcUrl: string;
  let accounts: Account[];
  let provider: RpcProvider;
  let coreClassHash: string;
  let quoterClassHash: string;
  let positionsClassHash: string;

  beforeAll(() => {
    coreClassHash = hash.computeContractClassHash(CoreCompiledContract);
    quoterClassHash = hash.computeContractClassHash(QuoterCompiledContract);
    positionsClassHash = hash.computeContractClassHash(
      PositionsCompiledContract
    );
  });

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

  let core: Contract;
  let quoter: Contract;
  let positions: Contract;

  beforeEach(async () => {
    core = await new ContractFactory(
      CoreCompiledContract,
      coreClassHash,
      accounts[0]
    ).deploy();
    quoter = await new ContractFactory(
      QuoterCompiledContract,
      quoterClassHash,
      accounts[0]
    ).deploy(core.address);
    positions = await new ContractFactory(
      PositionsCompiledContract,
      positionsClassHash,
      accounts[0]
    ).deploy(core.address, "https://f.ekubo.org/");
  });

  for (const poolCase of POOL_CASES) {
    describe(poolCase.name, () => {
      // set up the pool according to the pool case
      beforeEach(async () => {});

      // then test swap for each swap case
      for (const swapCase of SWAP_CASES) {
        it(`swap ${swapCase.amount} ${
          swapCase.isToken1 ? "token1" : "token0"
        }`, async () => {
          expect("result").toMatchSnapshot();
        });
      }
    });
  }

  afterAll(async () => {
    return new Promise((resolve) => {
      starknetProcess.on("close", () => {
        resolve(null);
      });
      starknetProcess.kill();
    });
  });
});
