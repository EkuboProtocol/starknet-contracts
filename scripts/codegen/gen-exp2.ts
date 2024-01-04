console.log(`
// Returns 2**n
fn exp2(n: u8) -> u128 {
    assert(n < 128, 'exp2');
    ${Array(127).fill(null).map((_, i) => {
    return `if (n == ${i}) { 0x${(2n ** BigInt(i)).toString(16)} }`
}).join('\nelse ')
    }
    else { 0x${(2n ** 127n).toString(16)} }
}`)