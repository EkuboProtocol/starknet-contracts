import { Account, CallData, ec, hash, RpcProvider, stark } from "starknet";

const DEVNET_URL = "http://127.0.0.1:5050";
export const provider: RpcProvider = new RpcProvider({
  nodeUrl: DEVNET_URL,
});

export async function setDevnetTime(time: number) {
  const response = await fetch(`${DEVNET_URL}/set_time`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: `{"time":${time}}`,
  });

  if (!response.ok) {
    throw new Error(`Failed to set time: ${await response.text()}`);
  }
}

const PREDECLARED_OZ_ACCOUNT_CLASS_HASH =
  "0x61dac032f228abef9c6626f995015233097ae253a7f72d68552db02f2971b8f";

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
    0
  );

  const account = new Account(provider, expectedAccountAddress, privateKey);

  const response = await fetch(`${DEVNET_URL}/mint`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: `{"address":"${account.address}","amount":10000000000000000000000000000,"unit":"WEI","lite":true}`,
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
    { maxFee: 1_000_000_000_000_000_000n, nonce: 1n }
  );

  await provider.waitForTransaction(transaction_hash, { retryInterval: 0 });

  return account;
}
