module deeptrade_core::multisig;

use multisig::multisig;
use sui::event;

// === Errors ===
const ENewAddressIsOldAddress: u64 = 1;

// === Structs ===
/// Configuration of the protocol's administrator multisig. Only a multisig account matching these
/// parameters can perform administrative actions requiring `AdminCap`
public struct MultisigConfig has key {
    id: UID,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
}

/// Capability to update the multisig config
public struct MultisigAdminCap has key, store {
    id: UID,
}

// === Events ===
public struct MultisigConfigUpdated has copy, drop {
    config_id: ID,
    old_public_keys: vector<vector<u8>>,
    new_public_keys: vector<vector<u8>>,
    old_weights: vector<u8>,
    new_weights: vector<u8>,
    old_threshold: u16,
    new_threshold: u16,
    old_address: address,
    new_address: address,
}

// Initialize multisig config object and send multisig admin cap to publisher
fun init(ctx: &mut TxContext) {
    let multisig_config = MultisigConfig {
        id: object::new(ctx),
        public_keys: vector::empty(),
        weights: vector::empty(),
        threshold: 0,
    };
    let multisig_admin_cap = MultisigAdminCap {
        id: object::new(ctx),
    };

    transfer::share_object(multisig_config);
    transfer::transfer(multisig_admin_cap, ctx.sender());
}

// === Public-Mutative Functions ===
public fun update_multisig_config(
    config: &mut MultisigConfig,
    _admin: &MultisigAdminCap,
    new_public_keys: vector<vector<u8>>,
    new_weights: vector<u8>,
    new_threshold: u16,
) {
    let old_public_keys = config.public_keys;
    let old_weights = config.weights;
    let old_threshold = config.threshold;

    let old_address = multisig::derive_multisig_address_quiet(
        old_public_keys,
        old_weights,
        old_threshold,
    );
    // Validates passed multisig parameters, aborting if they are invalid
    let new_address = multisig::derive_multisig_address_quiet(
        new_public_keys,
        new_weights,
        new_threshold,
    );

    assert!(old_address != new_address, ENewAddressIsOldAddress);

    config.public_keys = new_public_keys;
    config.weights = new_weights;
    config.threshold = new_threshold;

    event::emit(MultisigConfigUpdated {
        config_id: config.id.to_inner(),
        old_public_keys,
        new_public_keys,
        old_weights,
        new_weights,
        old_threshold,
        new_threshold,
        old_address,
        new_address,
    });
}

// === Public-View Functions ===
public fun public_keys(config: &MultisigConfig): vector<vector<u8>> { config.public_keys }

public fun weights(config: &MultisigConfig): vector<u8> { config.weights }

public fun threshold(config: &MultisigConfig): u16 { config.threshold }

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx); }

#[test_only]
public fun get_multisig_admin_cap_for_testing(ctx: &mut TxContext): MultisigAdminCap {
    MultisigAdminCap { id: object::new(ctx) }
}
