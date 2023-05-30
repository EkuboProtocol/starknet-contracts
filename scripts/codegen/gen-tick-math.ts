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


    console.log('let mut ratio = u256 { high: 1, low: 0 };')

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

// we want tick size such that x^(2^32) = 2**64
// that number squared represents the size of tick in price (not sqrt price)

// we want it to fit in an i32, and support prices from 2**128 to 2**-128, 
// meaning any price for 2 tokens with total supply of 2**128
const MAX_NUM_TICKS = (2n ** 23n) - 1n
// in other words, we want tickSize ** MAX_NUM_TICKS = 2**64, since we use sqrt ratios
// take log base tickSize of both sides:
// 2 ** 31 = log base x of 2**64
// 2 ** 31 / 64 = log base x of 2
// 2 ** 31 / 2**6 = log base x of 2
// 2 ** 25 = log base x of 2
// plug into wolfram
// https://www.wolframalpha.com/input?i=2+**+25+%3D+log+base+x+of+2
// x≈1.000000020657395950533543979520644024581777736970617015154729024967859069134592989763610673641979837435397245782267746869952775385202910986830121

// ^ scrapped this, too expensive to compute log

genTickMath({
    // 1/100th of a bips, ie a pips
    tickSize: new Decimal('1.000001'),
    fixedPointRadix: 128,
    maxRatio: new Decimal(2).pow(128),
});

