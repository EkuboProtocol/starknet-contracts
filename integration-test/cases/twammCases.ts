const THIRTY_BIPS_FEE = (2n ** 128n * 30n) / 10000n;
const ONE_PERCENT_FEE = (1n << 128n) / 100n;

export const TWAMM_POOL_CASES: Array<{
  name: string;
  pool: {
    startingTick: bigint;
    fee: bigint;
  };
  positions_liquidities: bigint[];
}> = [
  {
    name: "1e18 liquidity, starting price of 1, 0.3% fee",
    pool: {
      startingTick: 0n,
      fee: THIRTY_BIPS_FEE,
    },
    positions_liquidities: [10n ** 18n],
  },
  {
    name: "1e36 liquidity across 2 positions, starting price of 1, 1% fee",
    pool: {
      startingTick: 0n,
      fee: ONE_PERCENT_FEE,
    },
    positions_liquidities: [5n * 10n ** 35n, 5n * 10n ** 35n],
  },
  {
    name: "0 liquidity, starting price of 1, 1% fee",
    pool: {
      startingTick: 0n,
      fee: ONE_PERCENT_FEE,
    },
    positions_liquidities: [],
  },
  {
    name: "1e18 liquidity, starting price of 1, 1% fee",
    pool: {
      startingTick: 0n,
      fee: ONE_PERCENT_FEE,
    },
    positions_liquidities: [10n ** 18n],
  },
];

export const TWAMM_ORDER_CASES: Array<{
  name: string;
  orders: {
    relativeTimes: { start: number; end: number };
    isToken1: boolean;
    amount: bigint;
  }[];
}> = [
  {
    name: "no orders",
    orders: [],
  },
  {
    name: "selling 1e18 token0 per second for one period",
    orders: [
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: false,
        amount: 16n * 10n ** 18n,
      },
    ],
  },
  {
    name: "selling 1e18 token1 per second for one period",
    orders: [
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: true,
        amount: 16n * 10n ** 18n,
      },
    ],
  },
  {
    name: "selling 1e18 of both tokens per second for one period",
    orders: [
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: false,
        amount: 16n * 10n ** 18n,
      },
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: true,
        amount: 16n * 10n ** 18n,
      },
    ],
  },
  {
    name: "selling twice as much token1 as token0 for one period",
    orders: [
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: false,
        amount: 8n * 10n ** 18n,
      },
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: true,
        amount: 16n * 10n ** 18n,
      },
    ],
  },
  {
    name: "selling twice as much token0 as token1 for one period",
    orders: [
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: false,
        amount: 16n * 10n ** 18n,
      },
      {
        relativeTimes: { start: 0, end: 16 },
        isToken1: true,
        amount: 8n * 10n ** 18n,
      },
    ],
  },
];

export const TWAMM_ACTION_SETS: {
  name: string;
  actions: (
    { 
      after: number
    } & ({
      type: "execute_virtual_orders"
    } | {
      type: "swap";
      amount: bigint;
      isToken1: boolean;
      sqrtRatioLimit?: bigint;
      skipAhead?: bigint;
    })
  )[];
}[] = [
  {
    name: "execute at 0, 8 and 16 seconds",
    actions: [
      { after: 0, type: "execute_virtual_orders" },
      { after: 8, type: "execute_virtual_orders" },
      { after: 16, type: "execute_virtual_orders" },
    ],
  },
  {
    name: "swap 0 tokens at 0, 8 and 16 seconds",
    actions: [
      { after: 0, type: "swap", amount: 0n, isToken1: false },
      { after: 8, type: "swap", amount: 0n, isToken1: false },
      { after: 16, type: "swap", amount: 0n, isToken1: false },
    ],
  },
  {
    name: "swap 1e18 token0 tokens at 0, 8 and 16 seconds",
    actions: [
      { after: 0, type: "swap", amount: 10n ** 18n, isToken1: false },
      { after: 8, type: "swap", amount: 10n ** 18n, isToken1: false },
      { after: 16, type: "swap", amount: 10n ** 18n, isToken1: false },
    ],
  },
  {
    name: "swap 1e18 token1 tokens at 0, 8 and 16 seconds",
    actions: [
      { after: 0, type: "swap", amount: 10n ** 18n, isToken1: true },
      { after: 8, type: "swap", amount: 10n ** 18n, isToken1: true },
      { after: 16, type: "swap", amount: 10n ** 18n, isToken1: true },
    ],
  },
];
