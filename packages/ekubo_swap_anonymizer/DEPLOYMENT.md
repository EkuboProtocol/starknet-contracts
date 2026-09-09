# Mainnet deployment

Verified on 2026-09-08 at mainnet block 14588072 using `starknet_getClassHashAt`.

| Field | Value |
| --- | --- |
| Network | `SN_MAIN` |
| Address | `0x077f14f44633e8adb83ea8c816b9a0112d986147beddd9ed4a94b12ca6c8e447` |
| Sierra class hash | `0x753c2562f67422bfdfb8c57e079bb1cdcfcbb8067693f53161964e1281ae504` |
| Compiled class hash (local artifact) | `0x34f4e69d328bc36600e6b8343157aaa61ce27efae2c97ecbc9a50ff95da6695` |
| Contract source revision | `976fa9617e78cc55bd05859fb5a55b36f3fbc04a` |
| Privacy dependency revision | `3dfe66fe2b59d7b95709ec719547fa88b8ef63f9` |
| Scarb / Cairo | `2.20.0` |
| Sierra | `1.9.3` |
| Build | `scarb --release build` |
| Router | `0x04505a9f06f2bd639b6601f37a4dc0908bb70e8e0e0c34b1220827d64f4fc066` |
| Core | `0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b` |

The Sierra hash above was reproduced locally and matches the deployed contract. Test and formatting changes after the source revision must reproduce this hash before release. This record is a deployment compatibility check, not an independent security audit or proof of an end-to-end wallet transaction.

From this package directory, run `python3 scripts/fetch-dependencies.py` before building on a fresh machine. Scarb 2.20 can concurrently clone the privacy workspace's shared Git dependency into the same directory; the script fetches that source first using the revision in `Scarb.lock`. CI pins Scarb 2.20.0 and Starknet Foundry 0.62.1.

The interface uses Wallet API 0.10.3 for STRK20 requests and RPC 0.9.0 for public chain reads. These are separate protocols. Alchemy's configured mainnet endpoint was verified with RPC 0.9.0; the `/v0_10/` path was unavailable.
