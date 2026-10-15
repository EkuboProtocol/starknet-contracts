import { Decimal } from 'decimal.js'

function genTickMath({
    tickSize,
    fixedPointRadix,
    maxRatio,
}: { tickSize: Decimal, fixedPointRadix: number, maxRatio: Decimal }) {
    // log base 10 of 2**256 ~= 78, so 250 is plenty for maximum accuracy
    Decimal.config({ precision: 250, toExpPos: 999 })
    const QFP = new Decimal(2).pow(fixedPointRadix);

    const tickOfMaxRatio = maxRatio.ln().div(tickSize.ln())

    const sqrtTick = tickSize.sqrt()

    const numIterations = tickOfMaxRatio.ln().div(new Decimal(2).ln()).ceil().toNumber()

    console.log(`// tick size = ${tickSize.toPrecision(12).toString()}`)
    console.log(`// number of iterations = ${numIterations}`)
    console.log(`// denominator = 1<<${fixedPointRadix}`)

    console.log('let mut ratio = 0x100000000000000000000000000000000_u256;')

    for (let i = 0; i < numIterations; i++) {
        const tickMultiplier = sqrtTick.pow(new Decimal(2).pow(i));
        const inverse = QFP.div(tickMultiplier).round()
        const inverseStr = `0x${BigInt(inverse.toString()).toString(16)}`
        const tickBit = `0x${(1n << BigInt(i)).toString(16)}`

        if (i == 0) {
            console.log(`if ((tick.mag & ${tickBit}) != 0) { ratio = u256 { high: 0, low: ${inverseStr} }; }`)
        } else {
            console.log(`if ((tick.mag & ${tickBit}) != 0) { ratio = unsafe_mul_shift(ratio, ${inverseStr}); }`)
        }
    }

    console.log(`
    // if positive and non-zero, invert, because we were computng a negative value
    if (!tick.sign) {
        if (tick.mag != 0) {
            ratio = u256 {
                high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
            } / ratio;
        }
    }
`)
}

// we want it to fit in an i32, and support prices from 2**128 to 2**-128, 
// meaning any price for 2 tokens with total supply of 2**128
const MAX_NUM_TICKS = (2n ** 23n) - 1n

genTickMath({
    // 1/100th of a bips, ie a pips
    tickSize: new Decimal('1.000001'),
    fixedPointRadix: 128,
    maxRatio: new Decimal(2).pow(128),
});

