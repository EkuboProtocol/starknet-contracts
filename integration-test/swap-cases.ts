import { MAX_U128 } from "./constants";

const SWAP_CASES: Array<{
  amount: bigint;
  isToken1: boolean;
  priceLimit?: bigint;
  skipAhead?: number;
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
  {
    amount: MAX_U128,
    isToken1: true,
  },
  {
    amount: MAX_U128,
    isToken1: false,
  },
  {
    amount: -MAX_U128,
    isToken1: true,
  },
  {
    amount: -MAX_U128,
    isToken1: false,
  },
];
