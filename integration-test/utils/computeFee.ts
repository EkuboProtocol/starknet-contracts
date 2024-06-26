export function computeFee(x: bigint, fee: bigint): bigint {
  const p = x * fee;
  return p / 2n ** 128n + (p % 2n ** 128n !== 0n ? 1n : 0n);
}
