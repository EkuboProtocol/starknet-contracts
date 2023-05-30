
function indent(s: string, amt: number): string {
    return s.split(/\n/g).map(x => ' '.repeat(amt) + x).join('\n')
}

function genMaxValue(lower: bigint, upper: bigint, idt: number): string {
    if (lower == upper) {
        const val = (2n ** (lower + 1n)) - 1n
        const high = val >> 128n
        const low = val % (2n ** 128n)
        return `return u256 { high: 0x${high.toString(16)}, low: 0x${low.toString(16)} };`
    }

    if ((lower + 1n) == upper) {
        return indent(`if (n == ${lower}) {
    ${genMaxValue(lower, lower, idt + 2)}
} else {
    ${genMaxValue(upper, upper, idt + 2)}
}`, idt)
    }

    const mid = (lower + upper) / 2n

    return indent(`if (n > ${mid}) {
    ${genMaxValue(mid + 1n, upper, idt + 2)}
} else {
    ${genMaxValue(lower, mid, idt + 2)}
}`, idt)
}

console.log(`fn mask(n: u8) -> u256 {
    ${genMaxValue(0n, 255n, 0)}
}`)