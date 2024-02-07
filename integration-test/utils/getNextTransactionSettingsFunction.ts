import { Account, Nonce, num } from "starknet";

export type TxSettingsFn = () => { nonce: Nonce; maxFee: bigint };

export async function getNextTransactionSettingsFunction(
  account: Account
): Promise<TxSettingsFn> {
  let nonce: Nonce = await account.getNonce();
  return () => {
    const next = nonce;
    nonce = num.toHexString(BigInt(nonce) + 1n);
    return { nonce: next, maxFee: 1_000_000_000_000_000_000_000n };
  };
}
