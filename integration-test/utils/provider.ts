import { Account, CallData, ec, hash, RpcProvider, stark } from "starknet";

const DEVNET_URL = "http://127.0.0.1:5050";
export const provider: RpcProvider = new RpcProvider({
  nodeUrl: DEVNET_URL,
});

export async function setDevnetTime(time: number) {
  const response = await fetch(`${DEVNET_URL}/rpc`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: `{"jsonrpc": "2.0","id": "1","method": "devnet_setTime","params":{"time":${time}}}`,
  });

  if (!response.ok) {
    throw new Error(`Failed to set time: ${await response.text()}`);
  }
}

const PREDECLARED_OZ_ACCOUNT_CLASS_HASH =
  "0x05b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564";

export async function createAccount(): Promise<Account> {
  const privateKey = stark.randomAddress();
  const starkKeyPub = ec.starkCurve.getStarkKey(privateKey);

  // Calculate future address of the account
  const constructorCalldata = CallData.compile({
    publicKey: starkKeyPub,
  });

  const expectedAccountAddress = hash.calculateContractAddressFromHash(
    starkKeyPub,
    PREDECLARED_OZ_ACCOUNT_CLASS_HASH,
    constructorCalldata,
    0,
  );

  const account = new Account(provider, expectedAccountAddress, privateKey);

  const response = await fetch(`${DEVNET_URL}/rpc`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: `{"jsonrpc": "2.0","id": "1","method": "devnet_mint","params":{"address":"${account.address}","amount":10000000000000000000000000000,"unit":"FRI"}}`,
  });

  if (!response.ok) {
    throw new Error(`Failed to mint: ${await response.text()}`);
  }

  const { transaction_hash, contract_address } = await account.deployAccount(
    {
      classHash: PREDECLARED_OZ_ACCOUNT_CLASS_HASH,
      constructorCalldata,
      addressSalt: starkKeyPub,
    },
    { maxFee: 1_000_000_000_000_000_000n, nonce: 1n },
  );

  await provider.waitForTransaction(transaction_hash, { retryInterval: 0 });

  return account;
}
