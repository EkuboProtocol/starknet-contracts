// predeployed accounts, --seed 0
import { Account, Provider } from "starknet";

const accounts = [
  {
    address:
      "0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691",
    privateKey: "0x71d7bb07b9a64f6f78ac4c816aff4da9",
  },
  {
    address:
      "0x78662e7352d062084b0010068b99288486c2d8b914f6e2a55ce945f8792c8b1",
    privateKey: "0xe1406455b7d66b1690803be066cbe5e",
  },
  {
    address:
      "0x49dfb8ce986e21d354ac93ea65e6a11f639c1934ea253e5ff14ca62eca0f38e",
    privateKey: "0xa20a02f0ac53692d144b20cb371a60d7",
  },
];

export function getAccounts(provider: Provider) {
  return accounts.map(
    ({ address, privateKey }) => new Account(provider, address, privateKey)
  );
}
