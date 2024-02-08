export type i129 = { mag: bigint; sign: boolean };

export function toI129(x: bigint): i129 {
  return {
    mag: x < 0n ? x * -1n : x,
    sign: x < 0n,
  };
}

export function fromI129(x: { mag: bigint; sign: boolean }): bigint {
  return x.sign ? x.mag * -1n : x.mag;
}
