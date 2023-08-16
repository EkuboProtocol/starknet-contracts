import { spawn } from "child_process";
import { Provider } from "starknet";
import { getAccounts } from "./accounts";

export async function startDevnet() {
  console.log(
    "Starting starknet devnet",
    process.env.STARKNET_SIERRA_COMPILER_PATH ?? ""
  );

  const devnetProcess = spawn("starknet-devnet", [
    "--seed",
    "0",
    ...(process.env.STARKNET_SIERRA_COMPILER_PATH
      ? ["--sierra-compiler-path", process.env.STARKNET_SIERRA_COMPILER_PATH]
      : []),
  ]);

  // devnetProcess.stdout.on("data", (data) => console.log(data.toString("utf8")));
  // devnetProcess.stderr.on("data", (data) => console.log(data.toString("utf8")));

  const killedPromise = new Promise<null>((resolve) => {
    devnetProcess.on("close", () => resolve(null));
  });

  await new Promise((resolve, reject) => {
    devnetProcess.stdout.on("data", (data) => {
      if (
        data.toString("utf8").includes("Listening on http://127.0.0.1:5050/")
      ) {
        console.log("Starknet devnet started");

        resolve(null);
      }
    });
  });

  const provider = new Provider({
    sequencer: { baseUrl: "http://127.0.0.1:5050" },
  });
  const accounts = getAccounts(provider);

  return [devnetProcess, killedPromise, provider, accounts] as const;
}

export async function dumpState(path: string = "dump.bin") {
  const response = await fetch("http://127.0.0.1:5050/dump", {
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

export async function loadDump(path: string = "dump.bin") {
  const response = await fetch("http://127.0.0.1:5050/load", {
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
