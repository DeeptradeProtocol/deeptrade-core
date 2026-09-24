# Package Upgrade Provenance

How we upgrade `deeptrade-core` on mainnet so external observers can verify that
on-chain bytecode matches a specific git commit — without giving CI custody of
the `UpgradeCap`.

## Why this design

| Goal                                 | Choice                                                                                  |
| ------------------------------------ | --------------------------------------------------------------------------------------- |
| Upgrades require multisig            | `UpgradeCap` is owned by the admin multisig, not a CI deploy key                        |
| Observers can trust the build        | GitHub Actions builds bytecode and attests it with **SLSA Build L3** (Artifact Attestations via a reusable signer workflow) |
| CI must not be able to upgrade alone | Workflow is **provenance-only**: it never calls `signAndExecute` / never spends the cap |
| Post-upgrade source check            | `Published.toml` records address + `toolchain-version` for `sui client verify-source`   |

We intentionally do **not** reuse `publish_package.yml` / `sui-mvr-provenance` deploy-and-sign for upgrades: that path signs with `ED25519_PRIVATE_KEY` and would require the UpgradeCap to sit under a hot key.

Same idea as recording `toolchain-version` for source verification (see e.g. [DeepBook v7.0.0](https://github.com/MystenLabs/deepbookv3/releases/tag/v7.0.0)).

## Operator flow (upgrade)

1. Land the Move changes on the branch / commit you intend to upgrade from.
2. Ensure `packages/deeptrade-core/Published.toml` has:
   - correct `original-id` / `upgrade-capability`
   - `toolchain-version` and `build-config` matching the Sui CLI you will use
   - current `published-at` (package being upgraded **from**)
3. Fund the UpgradeCap holder address with enough SUI for gas (CLI auto-selects coins from `--sender`).
4. Run **Actions → Upgrade Package** (`upgrade_package.yml`) on that commit.
   - Input **`UPGRADE_CAP_ADDRESS_HOLDER`**: address that owns the UpgradeCap (usually the admin multisig). Used as `--sender`.
   - `upgrade-capability` is read from `Published.toml` (not an input).
5. Download artifacts from the workflow run:
   - `bytecode.dump.json`, `upgrade.manifest.json` (attested subjects)
   - `unsigned-upgrade.b64` — unsigned PTB (`authorize_upgrade` + `Upgrade` + `commit_upgrade`)
   - Provenance is in the repo [Attestations](https://github.com/DeeptradeProtocol/deeptrade-core/attestations) tab (not a separate `.intoto.jsonl` artifact)
6. CI already asserts the dump digest is embedded in `unsigned-upgrade.b64`. Observers should
   still rebuild locally and re-check; then multisig-sign `unsigned-upgrade.b64` and
   `sui client execute-signed-tx`.
7. After success, update locally:
   - `Published.toml`: set `published-at` to the **new** package ID; bump `version`
   - `examples/constants.ts`: `DEEPTRADE_CORE_PACKAGE_ID` (and any other changed IDs)
8. (Protocol versioning, if needed) enable / disable versions via admin multisig — see [versioning.md](./versioning.md).

## External observer checklist

### A. Before / during the upgrade (CI provenance)

1. Open the workflow run for the claimed commit; download the artifacts (including `unsigned-upgrade.b64`).
2. Verify SLSA Build L3 (GitHub Artifact Attestations). Pin the reusable signer workflow:

   ```bash
   gh attestation verify bytecode.dump.json \
     --repo DeeptradeProtocol/deeptrade-core \
     --signer-workflow DeeptradeProtocol/deeptrade-core/.github/workflows/attest-upgrade-subjects.yml
   ```

   (Same command for `upgrade.manifest.json`.) You can also browse
   [Attestations](https://github.com/DeeptradeProtocol/deeptrade-core/attestations).

3. Rebuild from that commit with the same Sui version as the manifest and compare digests:

   ```bash
   git checkout <git_commit>
   # install Sui matching upgrade.manifest.json → sui_version
   cd packages/deeptrade-core
   sui move build --dump-bytecode-as-base64 > /tmp/local.dump.json
   jq -c '.digest' bytecode.dump.json /tmp/local.dump.json   # must match
   ```

4. Confirm the **package digest** (`.digest` / `package_digest`) is what `authorize_upgrade` binds in `unsigned-upgrade.b64`.
5. Before signing: match **`ledger_transaction_hash`** from the manifest / job summary to Mysten Offline Signer / Ledger
   (`blake2b-256([0,0,0] || BCS(TransactionData))` as `0x…` hex). This is **not** the explorer transaction digest after execute.
6. Multisig-sign `unsigned-upgrade.b64` and `sui client execute-signed-tx`.

### B. After the upgrade (on-chain source verification)

Once `Published.toml` points at the **new** `published-at` (and `version` is bumped):

```bash
git checkout <commit that matches the upgrade>
cd packages/deeptrade-core
sui client verify-source
```

This rebuilds with `toolchain-version` from `Published.toml` and compares root package bytecode + linkage to the on-chain package. See [Sui source verification](https://docs.sui.io/develop/manage-packages/source-verification).

If metadata is incomplete, override explicitly:

```bash
sui client verify-source --toolchain-version 1.80.1
```

## What each check proves

| Check                         | Proves                                                                                 |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| GitHub attestation (L3) on `bytecode.dump.json` | Dump was attested by the isolated reusable signer workflow for this repo; not tampered after attestation (`--signer-workflow` pins L3) |
| Local rebuild digest match    | That dump matches this git tree + toolchain                                            |
| Digest ↔ upgrade tx (CI + observers) | Dump digest bytes appear in `unsigned-upgrade.b64` (CI fails the run if not) |
| Ledger transaction hash | Same `0x…` hex Offline signers / Ledger show for this unsigned PTB (intent-prefixed blake2b) |
| `sui client verify-source`    | Checked-out source + recorded toolchain match the **on-chain** package                 |

Attestation alone does not authorize or execute the upgrade; multisig signers remain the authority.

## Related files

- `.github/workflows/upgrade_package.yml` — provenance CI
- `.github/workflows/attest-upgrade-subjects.yml` — reusable L3 attestor (digest-only)
- `.github/workflows/publish_package.yml` — initial publish + MVR (separate, key-signed)
- `packages/deeptrade-core/Published.toml` — publication metadata
- [dev-notes.md](./dev-notes.md) — CLI upgrade commands
- [versioning.md](./versioning.md) — `enable_version` / `disable_version` after package upgrade
