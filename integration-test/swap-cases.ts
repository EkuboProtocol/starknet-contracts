export const SWAP_CASES: Array<{
  amount: bigint;
  isToken1: boolean;
  sqrtRatioLimit?: bigint;
  skipAhead?: bigint;
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
];
