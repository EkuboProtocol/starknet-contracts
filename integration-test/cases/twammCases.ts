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
  // {
  //   name: "0 liquidity, starting price of 1, 1% fee",
  //   pool: {
  //     startingTick: 0n,
  //     fee: ONE_PERCENT_FEE,
  //   },
  //   positions_liquidities: [],
  // },
  // {
  //   name: "1e18 liquidity, starting price of 1, 1% fee",
  //   pool: {
  //     startingTick: 0n,
  //     fee: ONE_PERCENT_FEE,
  //   },
  //   positions_liquidities: [10n ** 18n],
  // },
  {
    name: "1e18 liquidity, starting price of 1, 0.3% fee",
    pool: {
      startingTick: 0n,
      fee: THIRTY_BIPS_FEE,
    },
    positions_liquidities: [10n ** 18n],
  },
  // {
  //   name: "1e36 liquidity across 2 positions, starting price of 1, 1% fee",
  //   pool: {
  //     startingTick: 0n,
  //     fee: ONE_PERCENT_FEE,
  //   },
  //   positions_liquidities: [5n * 10n ** 35n, 5n * 10n ** 35n],
  // },
];

export const TWAMM_SWAP_CASES: Array<{
  name: string;
  orders: {
    relative_times: { start: number; end: number };
    is_token1: boolean;
    amount: bigint;
  }[];
  snapshot_times: number[];
}> = [
  {
    name: "selling 1e18 token0 per second for one period",
    orders: [
      {
        relative_times: { start: 0, end: 16 },
        is_token1: false,
        amount: 10n ** 18n,
      },
    ],
    snapshot_times: [0, 8, 16],
  },
  // {
  //   name: "no swap, time passes",
  //   orders: [],
  //   snapshot_times: [0, 1],
  // },
  // {
  //   name: "selling 1e18 token1 per second for one period",
  //   orders: [
  //     {
  //       relative_times: { start: 0, end: 16 },
  //       is_token1: true,
  //       amount: 10n ** 18n,
  //     },
  //   ],
  //   snapshot_times: [0, 8, 16],
  // },
];
