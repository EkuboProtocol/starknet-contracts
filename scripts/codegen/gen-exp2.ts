
function indent(s: string, amt: number): string {
    return s.split(/\n/g).map(x => ' '.repeat(amt) + x).join('\n')
}

function genExp2(lower: bigint, upper: bigint, idt: number): string {
    if (lower == upper) {
        const val = 2n ** lower
        return `0x${val.toString(16)}`
    }
    const mid = (lower + upper) / 2n


    if ((lower + 1n) == upper) {
        return indent(`if (n == ${lower}) {
    ${genExp2(lower, lower, idt + 2)}
} else {
    ${genExp2(upper, upper, idt + 2)}
}`, idt)
    }

    return indent(`if (n > ${mid}) {
    ${genExp2(mid + 1n, upper, idt + 2)}
} else {
    ${genExp2(lower, mid, idt + 2)}
}`, idt)
}

console.log(`
// Returns 2**n
fn exp2(n: u8) -> u128 {
    assert(n < 128, 'exp2');
    ${genExp2(0n, 127n, 0)}
}`)