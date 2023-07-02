import { ChildProcessByStdio, ChildProcessWithoutNullStreams, spawn, SpawnOptionsWithStdioTuple } from 'child_process'

const FEE_TOKEN = {
    Address: '0x49d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7',
    ClassHash: '0x6a22bf63c7bc07effa39a25dfbd21523d211db0100a0afd054d172b81840eaf',
    Symbol: 'ETH',
}

// accounts for seed 0
const ACCOUNTS = [
    {
        address: '0x7e00d496e324876bbc8531f2d9a82bf154d1a04a50218ee74cdd372f75a551a',
        publicKey: '0x7e52885445756b313ea16849145363ccb73fb4ab0440dbac333cf9d13de82b9',
        privateKey: '0xe3e70682c2094cac629f6fbed82c07cd'
    },
    {
        address: '0x69b49c2cc8b16e80e86bfc5b0614a59aa8c9b601569c7b80dde04d3f3151b79',
        publicKey: '0x175666e92f540a19eb24fa299ce04c23f3b75cb2d2332e3ff2021bf6d615fa5',
        privateKey: '0xf728b4fa42485e3a0a5d2f346baa9455'
    },
    {
        address: '0x7447084f620ba316a42c72ca5b8eefb3fe9a05ca5fe6430c65a69ecc4349b3b',
        publicKey: '0x58100ffde2b924de16520921f6bfe13a8bdde9d296a338b9469dd7370ade6cb',
        privateKey: '0xeb1167b367a9c3787c65c1e582e2e662'
    },
    {
        address: '0x3cad9a072d3cf29729ab2fad2e08972b8cfde01d4979083fb6d15e8e66f8ab1',
        publicKey: '0xff104dba23c3aec5eb7c74a4605c05ef81a29ac94621c71dd88907f196aa2b',
        privateKey: '0xf7c1bd874da5e709d4713d60c8a70639'
    },
    {
        address: '0x7f14339f5d364946ae5e27eccbf60757a5c496bf45baf35ddf2ad30b583541a',
        publicKey: '0x1f0eea3a599b1eec7e02053a2d9a2712efefc3f61265d4b3166c14ade4152d8',
        privateKey: '0xe443df789558867f5ba91faf7a024204'
    },
    {
        address: '0x27d32a3033df4277caa9e9396100b7ca8c66a4ef8ea5f6765b91a7c17f0109c',
        publicKey: '0x5801376a836c9feb6941157bee10f24d942efa42d6d5e90fef25349c9471816',
        privateKey: '0x23a7711a8133287637ebdcd9e87a1613'
    },
    {
        address: '0x19299c32cf2dcf9432a13c0cee07077d711faadd08f59049ca602e070c9ebb',
        publicKey: '0x5a5a41e723be9e339b73a41bd1de92cde8fa4ebf9022ca951a92b0ac95a3c44',
        privateKey: '0x1846d424c17c627923c6612f48268673'
    },
    {
        address: '0x1d07131135aeb92eea44a341d94a01161edb1adab4c98ac56523d24e00183aa',
        publicKey: '0x5f2aa391b1548fa0c5fb216fc7c424328ffb7d1c8e2a1ff614683cc31896ca3',
        privateKey: '0xfcbd04c340212ef7cca5a5a19e4d6e3c'
    },
    {
        address: '0x53c615080d35defd55569488bc48c1a91d82f2d2ce6199463e095b4a4ead551',
        publicKey: '0x2c94f628d125cd0e86eaefea735ba24c262b9a441728f63e5776661829a4066',
        privateKey: '0xb4862b21fb97d43588561712e8e5216a'
    },
    {
        address: '0x7f61fa3893ad0637b2ff76fed23ebbb91835aacd4f743c2347716f856438429',
        publicKey: '0xc11e246b1d54515a26204d2d3c8586ea25ed9eecae00df173405974cb86dbc',
        privateKey: '0x259f4329e6f4590b9a164106cf6a659e'
    }
]

const PREDEPLOYED_UDC = {
    Address: '0x41a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf',
    ClassHash: '0x7b3e05f48f0c69e4a65ce5e076a66271a527aff2c34ce1083ec6e1526997a69'
}

const URL = 'http://localhost:5051'

describe('core tests', () => {

    let starknetProcess: ChildProcessWithoutNullStreams

    beforeAll(() => {
        starknetProcess = spawn('starknet-devnet', ['--seed', '0'])

        return new Promise((resolve, reject) => {
            let resolved = false

            let timeout = setTimeout(() => {
                if (!resolved) {
                    reject(new Error('timed out waiting'))
                }
            }, 30_000)

            starknetProcess.stdout.on('data', (data) => {
                let str = data.toString('utf8');
                if (str.includes('Predeployed UDC')) {
                    resolved = true;
                    clearTimeout(timeout)
                    resolve(null)
                }
            })
        })
    })

    beforeEach(() => {
        console.log('reset the env')
    })

    it('works', () => {

    })

    afterAll(async () => {
        console.log('killing starknet-devnet')

        return new Promise(resolve => {
            starknetProcess.on('close', () => {
                console.log('closed')
                resolve(null);
            });
            starknetProcess.kill()
        });
    })
})