import { spawn } from "child_process";
import { Provider, ProviderInterface, ProviderOptions } from "starknet";
import { getAccounts } from "./accounts";

export class DevnetProvider extends Provider {
  private readonly port: number;

  constructor(port: number) {
    super({ sequencer: { baseUrl: `http://127.0.0.1:${port}` } });
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

export async function startDevnet(options?: {
  sierraCompilerPath?: string;
  port?: number;
}) {
  console.log("Starting starknet devnet", options?.sierraCompilerPath ?? "");

  const port = options?.port ?? 5050;
  const devnetProcess = spawn("starknet-devnet", [
    "--seed",
    "0",
    "--port",
    `${port}`,
    ...(options?.sierraCompilerPath
      ? ["--sierra-compiler-path", options.sierraCompilerPath]
      : []),
  ]);

  const killedPromise = new Promise<null>((resolve) => {
    devnetProcess.on("close", () => resolve(null));
  });

  await new Promise((resolve) => {
    const listener = (data: Buffer) => {
      if (data.toString("utf8").includes(`Listening on`)) {
        console.log("Starknet devnet started");
        devnetProcess.stdout.off("data", listener);

        resolve(null);
      }
    };

    devnetProcess.stdout.on("data", listener);
    devnetProcess.on("error", (error) => {
      console.error(`Error: ${error.message}`);
    });

    devnetProcess.on("exit", (code, signal) => {
      console.log(
        `Child process exited with code ${code} and signal ${signal}`
      );
    });
  });

  const provider = new DevnetProvider(port);
  const accounts = getAccounts(provider);

  return [devnetProcess, killedPromise, provider, accounts] as const;
}
