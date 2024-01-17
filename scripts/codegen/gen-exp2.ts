console.log(`
// Returns 2^n
fn exp2(n: u8) -> u128 {
    ${Array(127).fill(null).map((_, i) => {
    return `if (n == ${i}) { return 0x${(2n ** BigInt(i)).toString(16)}; }`
}).join('\n')
    }
    assert(n == 127, 'exp2');
    0x${(2n ** BigInt(127)).toString(16)}
}`)