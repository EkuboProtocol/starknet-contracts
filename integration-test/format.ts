function numberToFixedPoint128(x: number): bigint {
  let power = 0;
  while (x % 1 !== 0) {
    power++;
    x *= 10;
  }

  return (BigInt(x) * 2n ** 128n) / 10n ** BigInt(power);
}
