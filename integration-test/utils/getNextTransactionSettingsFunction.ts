import { Account, Nonce, num } from "starknet";

export type TxSettingsFn = () => { nonce: Nonce; maxFee: bigint };

export async function getNextTransactionSettingsFunction(
  account: Account,
  nonce?: Nonce
): Promise<TxSettingsFn> {
  nonce = nonce ?? (await account.getNonce());
  return () => {
    const next = nonce;
    nonce = num.toHexString(BigInt(nonce) + 1n);
    return { nonce: next, maxFee: 1_000_000_000_000_000_000_000n };
  };
}
