let d: any;

export async function load() {
  return fetch("http://127.0.0.1:5050/load", {
    method: "post",
    body: JSON.stringify(d),
    headers: { "content-type": "application/json" },
  });
}

export async function dump() {
  const res = await fetch("http://127.0.0.1:5050/dump", { method: "post" });
  d = await res.json();
}

export async function reset() {
  await fetch("http://127.0.0.1:5050/reset", { method: "post" });
}
