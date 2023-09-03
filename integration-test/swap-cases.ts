export const SWAP_CASES: Array<{
  only?: true;
  amount: bigint;
  isToken1: boolean;
  sqrtRatioLimit?: bigint;
  skipAhead?: bigint;
  amountLimit?: bigint;
}> = [
  {
    amount: 0n,
    isToken1: true,
  },
  {
    amount: 0n,
    isToken1: false,
  },
  {
    amount: 2n ** 96n,
    isToken1: false,
  },
  {
    amount: 2n ** 96n,
    isToken1: true,
  },
  {
    amount: 10n ** 18n,
    isToken1: false,
    skipAhead: 5n,
  },
  {
    amount: 10n ** 18n,
    isToken1: true,
    skipAhead: 5n,
  },
  {
    amount: -(10n ** 18n),
    isToken1: false,
    skipAhead: 5n,
  },
  {
    amount: -(10n ** 18n),
    isToken1: true,
    skipAhead: 5n,
  },
  {
    amount: 10n ** 18n,
    isToken1: false,
    skipAhead: 2n,
    sqrtRatioLimit: 1n << 127n,
  },
  {
    amount: 10n ** 18n,
    isToken1: true,
    skipAhead: 2n,
    sqrtRatioLimit: 1n << 129n,
  },
  {
    amount: -(10n ** 18n),
    isToken1: false,
    skipAhead: 2n,
    sqrtRatioLimit: 1n << 129n,
  },
  {
    amount: -(10n ** 18n),
    isToken1: true,
    skipAhead: 2n,
    sqrtRatioLimit: 1n << 127n,
  },
  // wrong direction
  {
    amount: 1n,
    isToken1: true,
    sqrtRatioLimit: 2n << 127n,
  },
  {
    amount: 1n,
    isToken1: true,
    sqrtRatioLimit: 2n << 127n,
  },
  {
    amount: 10_000n,
    isToken1: true,
  },
  {
    amount: 10_000n,
    isToken1: false,
  },
  {
    amount: -10_000n,
    isToken1: true,
  },
  {
    amount: -10_000n,
    isToken1: false,
  },
];
