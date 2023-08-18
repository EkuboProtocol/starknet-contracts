import { MAX_TICK, MIN_TICK } from "./constants";

const THIRTY_BIPS_FEE = (2n ** 128n * 30n) / 10000n;
const SIXTY_BIPS_TICK_SPACING = 5982n;

function nearest(tick: bigint, spacing: bigint): bigint {
  return (tick / spacing) * spacing;
}

export const POOL_CASES: Array<{
  only?: true;
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
    name: "1e18 full range liquidity, starting at price 1, tick_spacing=0.6%, fee=0.3%",
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
        liquidity: 10n ** 18n,
      },
    ],
  },
  {
    name: "1e18 liquidity above price, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [
      {
        bounds: {
          lower: 0n,
          upper: nearest(MAX_TICK, SIXTY_BIPS_TICK_SPACING),
        },
        liquidity: 10n ** 18n,
      },
    ],
  },
  {
    name: "1e18 liquidity below price, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [
      {
        bounds: {
          lower: nearest(MIN_TICK, SIXTY_BIPS_TICK_SPACING),
          upper: 0n,
        },
        liquidity: 10n ** 18n,
      },
    ],
  },
  {
    name: "overlapping positions asymmetric, starting at price 1, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: 0n,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [
      {
        bounds: {
          lower: SIXTY_BIPS_TICK_SPACING * -30n,
          upper: SIXTY_BIPS_TICK_SPACING * 30n,
        },
        liquidity: 100_000n,
      },
      {
        bounds: {
          lower: 0n,
          upper: SIXTY_BIPS_TICK_SPACING * 30n,
        },
        liquidity: 50_000n,
      },
      {
        bounds: {
          lower: SIXTY_BIPS_TICK_SPACING * -15n,
          upper: SIXTY_BIPS_TICK_SPACING * 10n,
        },
        liquidity: 80_000n,
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
  {
    name: "no liquidity, starting at min, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: MIN_TICK,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [],
  },
  {
    name: "no liquidity, starting at max, tick_spacing=0.6%, fee=0.3%",
    pool: {
      startingTick: MAX_TICK,
      tickSpacing: SIXTY_BIPS_TICK_SPACING,
      fee: THIRTY_BIPS_FEE,
    },
    positions: [],
  },
];
