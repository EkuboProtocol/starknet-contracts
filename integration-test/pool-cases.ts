import { MAX_TICK, MIN_TICK } from "./constants";

const THIRTY_BIPS_FEE = (2n ** 128n * 30n) / 10000n;
const SIXTY_BIPS_TICK_SPACING = 5982n;

function nearest(tick: bigint, spacing: bigint): bigint {
  return (tick / spacing) * spacing;
}

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
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [
      {
        bounds: {
          lower: nearest(MIN_TICK, SIXTY_BIPS_TICK_SPACING),
          upper: nearest(MAX_TICK, SIXTY_BIPS_TICK_SPACING),
        },
        liquidity: 10000n,
      },
    ],
  },
  {
    name: "no liquidity, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [],
  },
];
