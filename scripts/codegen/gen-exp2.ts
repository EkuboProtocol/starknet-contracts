console.log(`
// Returns 2^n
fn exp2(n: u8) -> u128 {
    match n {
        ${Array(127).fill(null).map((_, i) => {
            return `${i} => { 0x${(2n ** BigInt(i)).toString(16)} },`
        }).join('\n')
        }
        _ => {
            assert(n == 127, 'exp2');
            0x${(2n ** BigInt(127)).toString(16)}
        }
    }
}`)