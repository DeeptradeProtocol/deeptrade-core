# On-Chain Multi-Signature Enforcement

A critical aspect of this protocol's design is the guarantee that administrative functions are always under the control of a multi-signature wallet. We have implemented a novel on-chain pattern to enforce this, which differs from the standard approach. This document explains our rationale.

### The Goal: A Permanent, On-Chain Guarantee

Our primary goal is to provide a permanent, on-chain guarantee that the `AdminCap` can never be controlled by a single key. We want any external observer to be able to verify, at any time, that all sensitive administrative actions are subject to a multi-signature policy.

### The Problem with Standard Multi-Sig

The most common method for securing an `AdminCap` is to transfer it to a standard Sui multi-sig address.

- **The Weakness:** This approach carries a significant risk. The multi-sig wallet holding the `AdminCap` could, at any point, execute a transaction to transfer the `AdminCap` back to a regular, single-key address. This would silently remove the multi-sig protection and centralize control, defeating the original purpose.

### Our Solution: On-Chain Verification

To eliminate this weakness, our solution is to enforce the multi-sig check directly on-chain within every sensitive administrative function.

This is achieved through a shared `MultisigConfig` object that stores the official administrative multi-sig parameters (`public_keys`, `weights`, and `threshold`). All functions that require the `AdminCap` also require a reference to this `MultisigConfig` object.

Inside the function, the contract performs an on-chain verification to assert that the transaction sender's address matches the multi-sig address derived from the parameters stored in the `MultisigConfig` object. This ensures that only the authorized multi-sig wallet can execute the function.

```move
// Example from the `add_loyalty_level` function
public fun add_loyalty_level(
    loyalty_program: &mut LoyaltyProgram,
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    level: u8,
    fee_discount_rate: u64,
    ctx: &mut TxContext,
) {
    // This assertion guarantees the sender matches the multi-sig wallet
    // defined in the MultisigConfig object.
    multisig_config.validate_sender_is_admin_multisig(ctx);

    // ... function logic continues
}
```

### Rationale and Benefits

1.  **Immutability:** The multi-sig policy is enforced by the contract code itself. It cannot be bypassed or disabled without a full contract upgrade. The `AdminCap` is, by this design, permanently locked to a multi-sig governance model.
2.  **Transparency & Verifiability:** This is the most significant benefit. Any external party can audit any administrative transaction on the blockchain. By inspecting the transaction's inputs, they can retrieve the `MultisigConfig` object's ID. They can then query the state of this object to see the public keys, weights, and threshold used, and cryptographically verify that the action was authorized by the declared multi-sig policy.

### Acknowledged Trade-offs

We recognize that this approach comes with a primary trade-off:

- **Operational Security Exposure:** The full list of public keys participating in the multi-sig is publicly visible by inspecting the on-chain `MultisigConfig` object. We believe this is an acceptable trade-off for the absolute on-chain transparency and security it provides.
- **Not a Silver Bullet:** This on-chain mechanism does not, and cannot, replace the need for robust internal key management processes. The ultimate security of the system still relies on the signers protecting their individual keys and verifying the transactions they sign.
