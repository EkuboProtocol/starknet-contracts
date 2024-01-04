console.log(`
// Returns (2**n) - 1
fn mask(n: u8) -> u128 {
    assert(n < 128, 'mask');
    ${Array(127).fill(null).map((_, i) => {
    return `if (n == ${i}) { 0x${(2n ** BigInt(i + 1) - 1n).toString(16)} }`
}).join('\nelse ')
    }
    else { 0x${(2n ** 128n - 1n).toString(16)} }
}`)