import { MAX_TICK, MIN_TICK } from "./constants";

const THIRTY_BIPS_FEE = (2n ** 128n * 30n) / 10000n;
const TICK_SPACING_60_BIPS = 5982n;
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
    name: "full range liquidity, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: TICK_SPACING_60_BIPS,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [
      { bounds: { lower: MIN_TICK, upper: MAX_TICK }, liquidity: 10000n },
    ],
  },
  {
    name: "no liquidity, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: TICK_SPACING_60_BIPS,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [],
  },
];
