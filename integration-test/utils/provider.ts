import { Account, num, RpcProvider } from "starknet";

export const provider: RpcProvider = new RpcProvider({
  nodeUrl: "http://127.0.0.1:5050",
});

const ACCOUNTS = [
  {
    address: 0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691n,
    privateKey: 0x71d7bb07b9a64f6f78ac4c816aff4da9n,
  },
  {
    address: 0x78662e7352d062084b0010068b99288486c2d8b914f6e2a55ce945f8792c8b1n,
    privateKey: 0xe1406455b7d66b1690803be066cbe5en,
  },
  {
    address: 0x49dfb8ce986e21d354ac93ea65e6a11f639c1934ea253e5ff14ca62eca0f38en,
    privateKey: 0xa20a02f0ac53692d144b20cb371a60d7n,
  },
  {
    address: 0x4f348398f859a55a0c80b1446c5fdc37edb3a8478a32f10764659fc241027d3n,
    privateKey: 0xa641611c17d4d92bd0790074e34beeb7n,
  },

  {
    address: 0xd513de92c16aa42418cf7e5b60f8022dbee1b4dfd81bcf03ebee079cfb5cb5n,
    privateKey: 0x5b4ac23628a5749277bcabbf4726b025n,
  },
  {
    address: 0x1e8c6c17efa3a047506c0b1610bd188aa3e3dd6c5d9227549b65428de24de78n,
    privateKey: 0x836203aceb0e9b0066138c321dda5ae6n,
  },
  {
    address: 0x557ba9ef60b52dad611d79b60563901458f2476a5c1002a8b4869fcb6654c7en,
    privateKey: 0x15b5e3013d752c909988204714f1ff35n,
  },
  {
    address: 0x3736286f1050d4ba816b4d56d15d80ca74c1752c4e847243f1da726c36e06fn,
    privateKey: 0xa56597ba3378fa9e6440ea9ae0cf2865n,
  },
  {
    address: 0x4d8bb41636b42d3c69039f3537333581cc19356a0c93904fa3e569498c23ad0n,
    privateKey: 0xb467066159b295a7667b633d6bdaabacn,
  },
  {
    address: 0x4b3f4ba8c00a02b66142a4b1dd41a4dfab4f92650922a3280977b0f03c75ee1n,
    privateKey: 0x57b2f8431c772e647712ae93cc616638n,
  },
].map(
  (a) =>
    new Account(
      provider,
      num.toHexString(a.address),
      num.toHexString(a.privateKey)
    )
);

class AccountPool {
  private inUse: { [index: number]: true } = {};
  private queue: ((account: Account) => void)[] = [];

  public get(): Promise<Account> {
    const next = ACCOUNTS.findIndex((_, ix) => !this.inUse[ix]);

    if (next !== -1) {
      this.inUse[next] = true;
      return Promise.resolve(ACCOUNTS[next]);
    }

    return new Promise((resolve) => {
      this.queue.push(resolve);
    });
  }

  public release(account: Account): void {
    if (this.queue.length) {
      const next = this.queue.shift();
      next(account);
    } else {
      delete this.inUse[ACCOUNTS.findIndex((a) => a === account)];
    }
  }
}

export const accountPool = new AccountPool();
