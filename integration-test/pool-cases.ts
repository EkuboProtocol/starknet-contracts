import { MAX_TICK, MIN_TICK } from "./constants";

const THIRTY_BIPS = (2n ** 128n * 30n) / 10000n;
export const POOL_CASES: Array<{
  name: string;
  pool: {
    startingTick: bigint;
    tickSpacing: bigint;
    fee: bigint;
  };
  positions: {
    bounds: {
      lower: bigint;
      upper: bigint;
    };
    liquidity: bigint;
  }[];
}> = [
  {
    name: "no liquidity, starting at price 1, tick_spacing==1, fee=0.003",
    pool: { startingTick: 0n, tickSpacing: 1n, fee: THIRTY_BIPS },
    positions: [],
  },
  {
    name: "full range liquidity, starting at price 1, tick_spacing==1, fee=0.003",
    pool: {
      startingTick: 0n,
      tickSpacing: 1n,
      fee: THIRTY_BIPS,
    },
    positions: [
      { bounds: { lower: MIN_TICK, upper: MAX_TICK }, liquidity: 10000n },
    ],
  },
];
