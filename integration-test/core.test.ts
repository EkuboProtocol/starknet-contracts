import { ChildProcessByStdio, ChildProcessWithoutNullStreams, spawn, SpawnOptionsWithStdioTuple } from 'child_process'
import fs from "fs";

import {
    defaultProvider,
    ec,
    json,
    SequencerProvider,
    Account,
    Provider,
} from "starknet";

describe('core tests', () => {
    let starknetProcess: ChildProcessWithoutNullStreams
    let rpcUrl: string
    let accounts: { address: string, privateKey: string, publicKey: string }[]
    let provider: SequencerProvider

    beforeAll(() => {
        starknetProcess = spawn('katana', ['--seed', '0'])

        return new Promise((resolve) => {
            starknetProcess.stdout.once('data', (data) => {
                let str = data.toString('utf8');
                // console.log(str);
                rpcUrl = /(http:\/\/[\w\.:\d]+)/g.exec(str)?.[1]
                rpcUrl = rpcUrl.replace(/0\.0\.0\.0/, 'localhost')
                // rpcUrl = 'http://localhost:5050'
                provider = new SequencerProvider({ baseUrl: rpcUrl, gatewayUrl: rpcUrl })
                accounts = [...str.matchAll(/\|\s+Account Address\s+\|\s+(0x[a-f0-9]+)\s+\|\s+Private key\s+\|\s+(0x[a-f0-9]+)\s+\|\s+Public key\s+\|\s+(0x[a-f0-9]+)/gi)]
                    .map(match => ({ address: match[1], privateKey: match[2], publicKey: match[3] }))
                resolve(null)
            })
        })
    })

    beforeEach(async () => {
        console.log(await provider.getBlock('latest'))
        console.log(await provider.getChainId())
    })

    it('works', () => {

    })

    afterAll(async () => {
        console.log('killing devnet')

        return new Promise(resolve => {
            starknetProcess.on('close', () => {
                console.log('closed');
                resolve(null);
            });
            starknetProcess.kill()
        });
    })
})