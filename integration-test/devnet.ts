import { spawn } from "child_process";
import { Provider, ProviderInterface, ProviderOptions } from "starknet";
import { getAccounts } from "./accounts";

export class DevnetProvider extends Provider {
  private readonly port: number;

  constructor(port: number = 5050) {
    super({ rpc: { nodeUrl: `http://127.0.0.1:${port}` } });
    this.port = port;
  }

  async dumpState(path: string = "dump.bin") {
    const response = await fetch(`http://127.0.0.1:${this.port}/dump`, {
      method: "post",
      body: JSON.stringify({ path }),
      headers: { "content-type": "application/json" },
    });
    if (!response.ok) {
      throw new Error(`Failed to save state: ${await response.text()}`);
    } else {
      const blob = await response.blob();
    }
  }

  async loadDump(path: string = "dump.bin") {
    const response = await fetch(`http://127.0.0.1:${this.port}/load`, {
      method: "post",
      body: JSON.stringify({
        path,
      }),
      headers: { "content-type": "application/json" },
    });
    if (!response.ok) {
      throw new Error(`Failed to load state: ${await response.text()}`);
    }
  }
}
