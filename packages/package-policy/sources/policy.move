/// This module implements a generic, enforceable, event-emitting custom upgrade policy.
/// The code within is general-purpose and can be used to govern
/// the upgradeability of any Sui package.
///
/// It uses the **Direct Wrapping** mechanism to implement an **object locking** pattern,
/// where the real `sui::package::UpgradeCap` is locked inside a custom `PolicyCap` object.
///
/// This implementation is based on the official Sui documentation:
/// - Custom Upgrade Policies: https://docs.sui.io/concepts/sui-move-concepts/packages/custom-policies
/// - Wrapped Objects: https://docs.sui.io/concepts/object-ownership/wrapped
///
/// To enforce this policy for a given package, its owner must
/// perform a one-time call to `policy::create`, which consumes the original
/// `UpgradeCap` and returns the `PolicyCap`.
/// All future upgrades for that package must then use the functions in this module.
module package_policy::policy;

use sui::event;
use sui::package::{Self, UpgradeCap, UpgradeReceipt, UpgradeTicket};

/// A custom capability object that wraps the real `UpgradeCap`.
/// The owner of this object has the authority to upgrade the target package
/// according to the rules in this module.
public struct PolicyCap has key, store {
    id: UID,
    /// The original UpgradeCap for the package this policy governs.
    upgrade_cap: UpgradeCap,
}

/// Event emitted when a new PolicyCap is created, locking an UpgradeCap.
public struct PolicyCreated has copy, drop {
    /// The ID of the newly created PolicyCap object.
    policy_cap_id: ID,
    /// The ID of the package this policy now governs.
    governed_package_id: ID,
}

/// Event emitted when an upgrade is authorized, before it is committed.
public struct UpgradeAuthorized has copy, drop {
    /// The ID of the PolicyCap object used for authorization.
    policy_cap_id: ID,
    /// The ID of the package being upgraded.
    governed_package_id: ID,
    /// The digest of the new package bytecode.
    digest: vector<u8>,
}

/// Event emitted when the contract is upgraded.
public struct ContractUpgraded has copy, drop {
    old_contract: ID,
    new_contract: ID,
}

/// Creates the `PolicyCap`, locking the original `UpgradeCap` inside it.
/// Emits a `PolicyCreated` event.
/// The new `PolicyCap` is returned to be handled by the caller.
public fun create(upgrade_cap: UpgradeCap, ctx: &mut TxContext): PolicyCap {
    let governed_package_id = upgrade_cap.package();

    let policy_cap = PolicyCap {
        id: object::new(ctx),
        upgrade_cap,
    };

    event::emit(PolicyCreated {
        policy_cap_id: object::id(&policy_cap),
        governed_package_id,
    });

    policy_cap
}

/// Authorize a contract upgrade, emitting an `UpgradeAuthorized` event.
/// This returns an `UpgradeTicket` and requires the `PolicyCap`.
public fun authorize_upgrade(
    policy_cap: &mut PolicyCap,
    policy: u8,
    digest: vector<u8>,
): UpgradeTicket {
    event::emit(UpgradeAuthorized {
        policy_cap_id: object::id(policy_cap),
        governed_package_id: policy_cap.upgrade_cap.package(),
        digest,
    });

    package::authorize_upgrade(&mut policy_cap.upgrade_cap, policy, digest)
}

/// Finalize an upgrade and emit the `ContractUpgraded` event.
/// This consumes the `UpgradeReceipt` and requires the `PolicyCap`.
public fun commit_upgrade(policy_cap: &mut PolicyCap, receipt: UpgradeReceipt) {
    // Get the old package ID from the cap before it's mutated.
    let old_contract = policy_cap.upgrade_cap.package();

    // Commit the upgrade. This consumes the receipt and mutates the
    // `upgrade_cap` field, updating its `package` field to the new ID.
    package::commit_upgrade(&mut policy_cap.upgrade_cap, receipt);

    // Get the new package ID from the now-updated cap.
    let new_contract = policy_cap.upgrade_cap.package();

    // Emit an event reflecting the package ID change.
    event::emit(ContractUpgraded { old_contract, new_contract });
}
