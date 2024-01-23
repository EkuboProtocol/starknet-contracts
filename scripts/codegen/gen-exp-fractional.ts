import {Decimal} from 'decimal.js'

Decimal.config({precision: 1000, toExpPos: 999})

function genExpFractionalInput({
                                   base: rawBase,
                                   maxInput,
                                   inputFixedPointRadix,
                                   outputFixedPointRadix,
                               }: {
    base: Decimal,
    maxInput: Decimal,
    inputFixedPointRadix: number,
    outputFixedPointRadix: number,
}) {
    const base = rawBase.pow(new Decimal(1).div(new Decimal(2).pow(inputFixedPointRadix)))
    // log base 10 of 2**256 ~= 78, so 250 is plenty for maximum accuracy
    const QFP = new Decimal(2).pow(outputFixedPointRadix);

    const maxInputRaw = maxInput.mul(new Decimal(2).pow(inputFixedPointRadix))

    const numIterations = maxInputRaw.ln().div(new Decimal(2).ln()).ceil().toNumber()

    console.log(`// base = ${base.toPrecision(12).toString()}`)
    console.log(`// number of iterations = ${numIterations}`)
    console.log(`// denominator = 1<<${outputFixedPointRadix}`)


    console.log('let mut ratio = 0x100000000000000000000000000000000_u256;')

    for (let i = 0; i < numIterations; i++) {
        const tickMultiplier = base.pow(new Decimal(2).pow(i));
        const inverse = QFP.div(tickMultiplier).round()
        const inverseBigInt = BigInt(inverse.toString());
        if (inverseBigInt === 0n) break
        const inverseStr = `0x${inverseBigInt.toString(16)}`
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

genExpFractionalInput({
    base: Decimal.exp('1.0000000000000000000542101086242752217018420079820249449562765347'),
    maxInput: new Decimal(2).pow(64),
    inputFixedPointRadix: 64,
    outputFixedPointRadix: 128,
});

