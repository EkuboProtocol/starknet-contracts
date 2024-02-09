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
];

export const TWAMM_SWAP_CASES: Array<{ name: string }> = [
  {
    name: "no swap, time passes",
  },
];
