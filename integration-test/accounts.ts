// predeployed accounts, --seed 0
import { Account, Provider } from "starknet";

const accounts = [
  {
    address:
      "0x7e00d496e324876bbc8531f2d9a82bf154d1a04a50218ee74cdd372f75a551a",
    privateKey: "0xe3e70682c2094cac629f6fbed82c07cd",
  },
  {
    address:
      "0x69b49c2cc8b16e80e86bfc5b0614a59aa8c9b601569c7b80dde04d3f3151b79",
    privateKey: "0xf728b4fa42485e3a0a5d2f346baa9455",
  },
  {
    address:
      "0x7447084f620ba316a42c72ca5b8eefb3fe9a05ca5fe6430c65a69ecc4349b3b",
    privateKey: "0xeb1167b367a9c3787c65c1e582e2e662",
  },
];

export function getAccounts(provider: Provider) {
  return accounts.map(
    ({ address, privateKey }) => new Account(provider, address, privateKey)
  );
}
