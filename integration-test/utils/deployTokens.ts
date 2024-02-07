import { Account } from "starknet";
import { TxSettingsFn } from "./getNextTransactionSettingsFunction";

export async function deployTokens({
  classHash,
  deployer,
  getTxSettings,
}: {
  deployer: Account;
  classHash: string;
  getTxSettings: TxSettingsFn;
}): Promise<[token0: string, token1: string]> {
  const {
    contract_address: [tokenAddressA],
  } = await deployer.deploy(
    {
      classHash: classHash,

      constructorCalldata: [deployer.address, (1n << 128n) - 1n],
    },
    getTxSettings()
  );

  const {
    contract_address: [tokenAddressB],
  } = await deployer.deploy(
    {
      classHash: classHash,
      constructorCalldata: [deployer.address, (1n << 128n) - 1n],
    },
    getTxSettings()
  );

  const [token0, token1] =
    BigInt(tokenAddressA) < BigInt(tokenAddressB)
      ? [tokenAddressA, tokenAddressB]
      : [tokenAddressB, tokenAddressA];

  return [token0, token1];
}
