import Decimal from "decimal.js-light";

export function formatPrice(sqrtRatioLimit: bigint) {
  return new Decimal(sqrtRatioLimit.toString())
    .div(new Decimal(2).pow(128))
    .pow(2)
    .toSignificantDigits(6)
    .toString();
}
