import Decimal from "decimal.js-light";

function amount0Delta({
  liquidity,
  sqrtRatioLower,
  sqrtRatioUpper,
}: {
  liquidity: bigint;
  sqrtRatioLower: bigint;
  sqrtRatioUpper: bigint;
}) {
  const numerator = (liquidity << 128n) * (sqrtRatioUpper - sqrtRatioLower);

  const divOne =
    numerator / sqrtRatioUpper + (numerator % sqrtRatioUpper === 0n ? 0n : 1n);

  return divOne / sqrtRatioLower + (divOne % sqrtRatioLower === 0n ? 0n : 1n);
}

function amount1Delta({
  liquidity,
  sqrtRatioLower,
  sqrtRatioUpper,
}: {
  liquidity: bigint;
  sqrtRatioLower: bigint;
  sqrtRatioUpper: bigint;
}) {
  const numerator = liquidity * (sqrtRatioUpper - sqrtRatioLower);
  const result =
    (numerator % (1n << 128n) !== 0n ? 1n : 0n) + numerator / (1n << 128n);
  return result;
}

function tickToSqrtRatio(tick: bigint) {
  return BigInt(
    new Decimal("1.000001")
      .sqrt()
      .pow(new Decimal(Number(tick)))
      .mul(new Decimal(2).pow(128))
      .toFixed(0)
  );
}

export function getAmountsForLiquidity({
  bounds,
  liquidity,
  tick,
}: {
  bounds: { lower: bigint; upper: bigint };
  liquidity: bigint;
  tick: bigint;
}): { amount0: bigint; amount1: bigint } {
  if (tick < bounds.lower) {
    return {
      amount0: amount0Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
      amount1: 0n,
    };
  } else if (tick < bounds.upper) {
    return {
      amount0: amount0Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(tick),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
      amount1: amount1Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(tick),
      }),
    };
  } else {
    return {
      amount0: 0n,
      amount1: amount1Delta({
        liquidity,
        sqrtRatioLower: tickToSqrtRatio(bounds.lower),
        sqrtRatioUpper: tickToSqrtRatio(bounds.upper),
      }),
    };
  }
}
