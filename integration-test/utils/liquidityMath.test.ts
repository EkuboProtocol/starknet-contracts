import { getAmountsForLiquidity } from "./liquidityMath";
import { describe, it, expect } from "vitest";

describe(getAmountsForLiquidity, () => {
  it("tick below range", () => {
    expect(
      getAmountsForLiquidity({
        bounds: {
          lower: 5982n * 15n,
          upper: 5982n * 30n,
        },
        liquidity: 100_000n,
        tick: 0n,
      })
    ).toMatchInlineSnapshot(`
{
  "amount0": 4195n,
  "amount1": 0n,
}
`);
  });

  it("tick above range", () => {
    expect(
      getAmountsForLiquidity({
        bounds: {
          lower: 5982n * -30n,
          upper: 5982n * -15n,
        },
        liquidity: 100_000n,
        tick: 0n,
      })
    ).toMatchInlineSnapshot(`
{
  "amount0": 0n,
  "amount1": 4195n,
}
`);
  });

  it("tick within range", () => {
    expect(
      getAmountsForLiquidity({
        bounds: {
          lower: 5982n * -30n,
          upper: 5982n * 30n,
        },
        liquidity: 100_000n,
        tick: 0n,
      })
    ).toMatchInlineSnapshot(`
{
  "amount0": 8583n,
  "amount1": 8583n,
}
`);
  });
});
