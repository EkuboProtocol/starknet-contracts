# Mainnet deployment

Deployed on 2026-09-09 and verified at mainnet block 14589345 using
`starknet_getClassHashAt`. This deployment includes the Router donation fix in [AUDIT.md](AUDIT.md).

| Field | Value |
| --- | --- |
| Network | `SN_MAIN` |
| Address | `0x029c55514b13a1198ff004ff4e52d282bf98daf4c5c0dfc0303c390ec6615c15` |
| Sierra class hash | `0x018820ff44dfc4f94ee1463a726093dda4327147bf87b570bb53591a7e65894f` |
| Compiled class hash (local and declared) | `0x553c784e57ec6eff1536e7cefc7a1ced33758fbcf2d13b43d87dcef44c1b618` |
| Contract source revision | `3a1c3d090ac6811f602b4e0a153d8c6b638e3c5c` |
| Privacy dependency revision | `3dfe66fe2b59d7b95709ec719547fa88b8ef63f9` |
| Scarb / Cairo | `2.20.0` |
| Sierra | `1.9.3` |
| Build | `scarb --release build` |
| Router | `0x04505a9f06f2bd639b6601f37a4dc0908bb70e8e0e0c34b1220827d64f4fc066` |
| Core | `0x00000005dd3d2f4429af886cd1a3b08289dbcea99a294197e9eb43b0e0325b4b` |

The local Sierra hash matches the deployed class. The local compiled class hash also
matches the declaration transaction's `compiled_class_hash`. Both transaction receipts
report `SUCCEEDED` and `ACCEPTED_ON_L2`:

- Declaration: [`0x07d3f041c9f29ec765dc6d4ca704d77580ba7587666143e882b36a4dd44e510a`](https://voyager.online/tx/0x07d3f041c9f29ec765dc6d4ca704d77580ba7587666143e882b36a4dd44e510a), block 14589290.
- Deployment: [`0x01394393aca812ffb25464315693d68d4734e556947f93b4045d83782c934ea9`](https://voyager.online/tx/0x01394393aca812ffb25464315693d68d4734e556947f93b4045d83782c934ea9), block 14589330.
- Constructor calldata: empty. UDC salt: `0x454b55424f5f414e4f4e595f5632`, non-unique.

This supersedes the initial helper at
`0x077f14f44633e8adb83ea8c816b9a0112d986147beddd9ed4a94b12ca6c8e447`
(class `0x753c2562f67422bfdfb8c57e079bb1cdcfcbb8067693f53161964e1281ae504`),
which still has the donation-griefing issue. The helper is immutable; the interface
must use the replacement address rather than treating this as an upgrade.

Subsequent test and documentation changes must reproduce these hashes before release.
This is deployment evidence, not proof of an end-to-end STRK20 wallet transaction.

From this package directory, run `python3 scripts/fetch-dependencies.py` before building on a fresh machine. Scarb 2.20 can concurrently clone the privacy workspace's shared Git dependency into the same directory; the script fetches that source first using the revision in `Scarb.lock`. CI pins Scarb 2.20.0 and Starknet Foundry 0.62.1.

The interface uses Wallet API 0.10.3 for STRK20 requests and RPC 0.9.0 for public chain reads. These are separate protocols. Alchemy's configured mainnet endpoint was verified with RPC 0.9.0; the `/v0_10/` path was unavailable.
