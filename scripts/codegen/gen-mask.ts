console.log(`
// Returns 2^(n+1) - 1
fn mask(n: u8) -> u128 {
    match n {
        ${Array(127).fill(null).map((_, i) => {
            return `${i} => { 0x${(2n ** BigInt(i + 1) - 1n).toString(16)} },`
        }).join('\n')
        }
        _ => {
            assert(n == 127, 'mask');
            0x${(2n ** 128n - 1n).toString(16)
        }
    }
}`)