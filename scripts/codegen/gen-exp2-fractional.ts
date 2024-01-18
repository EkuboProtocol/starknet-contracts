import {Decimal} from 'decimal.js'

function genTickMath({
                         base,
                         outputFixedPointRadix,
                         maxRatio,
                     }: { base: Decimal, outputFixedPointRadix: number, maxRatio: Decimal }) {
    // log base 10 of 2**256 ~= 78, so 250 is plenty for maximum accuracy
    Decimal.config({precision: 250, toExpPos: 999})
    const QFP = new Decimal(2).pow(outputFixedPointRadix);

    const tickOfMaxRatio = maxRatio.ln().div(base.ln())

    const numIterations = tickOfMaxRatio.ln().div(new Decimal(2).ln()).ceil().toNumber()

    console.log(`// base = ${base.toPrecision(12).toString()}`)
    console.log(`// number of iterations = ${numIterations}`)
    console.log(`// denominator = 1<<${outputFixedPointRadix}`)


    console.log('let mut ratio = 0x100000000000000000000000000000000_u256;')

    for (let i = 0; i < numIterations; i++) {
        const tickMultiplier = base.pow(new Decimal(2).pow(i));
        const inverse = QFP.div(tickMultiplier).round()
        const inverseStr = `0x${BigInt(inverse.toString()).toString(16)}`
        const tickBit = `0x${(1n << BigInt(i)).toString(16)}`

        if (i == 0) {
            console.log(`if ((x & ${tickBit}) != 0) { ratio = u256 { high: 0, low: ${inverseStr} }; }`)
        } else {
            console.log(`if ((x & ${tickBit}) != 0) { ratio = internal::unsafe_mul_shift(ratio, ${inverseStr}); }`)
        }
    }

    console.log(`
    if (x != 0) {
        ratio = u256 {
            high: 0xffffffffffffffffffffffffffffffff, low: 0xffffffffffffffffffffffffffffffff
        } / ratio;
    }
`)
}

genTickMath({
    base: new Decimal('1.0000000000000000000375755839507647455133556151917687744689917354'),
    outputFixedPointRadix: 128,
    maxRatio: new Decimal(2).pow(64),
});

