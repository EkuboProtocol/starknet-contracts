import { MAX_TICK, MIN_TICK } from "./constants";

export const POOL_CASES: Array<{
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
