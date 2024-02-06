export function toI129(x: bigint): { mag: bigint; sign: "0x1" | "0x0" } {
    return {
        mag: x < 0n ? x * -1n : x,
        sign: x < 0n ? "0x1" : "0x0",
    };
}

export function fromI129(x: { mag: bigint; sign: boolean }): bigint {
  return x.sign ? x.mag * -1n : x.mag;
}