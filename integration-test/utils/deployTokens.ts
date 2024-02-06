import { Account } from "starknet";

export async function deployTokens({
  classHash,
  deployer,
}: {
  deployer: Account;
  classHash: string;
}): Promise<[token0: string, token1: string]> {
  const {
    contract_address: [tokenAddressA],
  } = await deployer.deploy({
    classHash: classHash,

    constructorCalldata: [deployer.address, (1n << 128n) - 1n],
  });

  const {
    contract_address: [tokenAddressB],
  } = await deployer.deploy({
    classHash: classHash,
    constructorCalldata: [deployer.address, (1n << 128n) - 1n],
  });

  const [token0, token1] =
    BigInt(tokenAddressA) < BigInt(tokenAddressB)
      ? [tokenAddressA, tokenAddressB]
      : [tokenAddressB, tokenAddressA];

  return [token0, token1];
}
