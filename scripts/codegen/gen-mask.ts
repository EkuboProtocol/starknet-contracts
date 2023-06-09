
function indent(s: string, amt: number): string {
    return s.split(/\n/g).map(x => ' '.repeat(amt) + x).join('\n')
}

function genMask(lower: bigint, upper: bigint, idt: number): string {
    if (lower == upper) {
        const val = (2n ** (lower + 1n)) - 1n
        return `0x${val.toString(16)}`
    }

    if ((lower + 1n) == upper) {
        return indent(`if (n == ${lower}) {
    ${genMask(lower, lower, idt + 2)}
} else {
    ${genMask(upper, upper, idt + 2)}
}`, idt)
    }

    const mid = (lower + upper) / 2n

    return indent(`if (n > ${mid}) {
    ${genMask(mid + 1n, upper, idt + 2)}
} else {
    ${genMask(lower, mid, idt + 2)}
}`, idt)
}

console.log(`
// Returns (2**n) - 1
fn mask(n: u8) -> u128 {
    assert(n < 128, 'mask');
    ${genMask(0n, 255n, 0)}
}

// Returns (2**n) - 1 for n > 127
fn mask_big(n: u8) -> u256 {
    if (n > 127) {
        u256 { high: mask(n - 128), low: 0 }
    } else {
        u256 { high: 0, low: exp2(n) }
    }
}`)