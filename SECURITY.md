# Security Policy

Thank you for helping keep Deeptrade Core secure.

## Reporting a vulnerability

Please email **security@deeptrade.io**. Do not open a public GitHub issue or pull request for a vulnerability.

Include as much detail as you can (affected package version or package ID, steps to reproduce, impact, and a proof of concept if available). We prefer reports that demonstrate a concrete impact on funds, fee accounting, or admin controls.

## Scope

- The on-chain Move package at `packages/deeptrade-core`, published on Sui mainnet as package version 2 and registered on the Move Registry as [`@deeptrade/deeptrade-core`](https://www.moveregistry.com/package/@deeptrade/deeptrade-core).
- Integration assumptions with DeepBook and Pyth that this package relies on (see `docs/oracle-pricing-security.md`).

Out of scope: the Deeptrade web frontend, indexer, and TypeScript admin tooling under `examples/` and `scripts/`.

## Response

We aim to acknowledge reports within **72 hours** and to share an initial fix plan within **7 days** for confirmed high or critical issues. Disclosure timing is coordinated with the reporter after a fix is available or a mitigation is in place.

## Existing audits

Deeptrade Core was audited by MoveBit (October 2025). All identified issues were resolved before mainnet deployment.

- [Audit report (in-repo)](./audits/Deeptrade%20Audit%20Report-2025-10-9.pdf)
- [Official mirror](http://movebit.xyz/reports/20251009-Deeptrade-Final-Audit-Report.pdf)

## Further reading

- [Oracle pricing security](docs/oracle-pricing-security.md)
- [Multisig](docs/multisig.md)
- [Upgrade provenance (SLSA Build L3)](docs/upgrade-provenance.md)
