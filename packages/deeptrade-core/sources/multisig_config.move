module deeptrade_core::multisig_config;

use multisig::multisig;
use sui::event;

// === Errors ===
const ENewAddressIsOldAddress: u64 = 1;
const ESenderIsNotValidMultisig: u64 = 2;
const EMultisigConfigAlreadyInitialized: u64 = 3;
const EMultisigConfigNotInitialized: u64 = 4;
const ETooFewSigners: u64 = 5;

// === Constants ===
const MIN_SIGNERS: u64 = 2;

// === Structs ===
/// Configuration of the protocol's administrator multisig. Only a multisig account matching these
/// parameters can perform administrative actions requiring `AdminCap`
public struct MultisigConfig has key {
    id: UID,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    initialized: bool,
}

/// Capability to update the multisig config
public struct MultisigAdminCap has key, store {
    id: UID,
}

// === Events ===
public struct MultisigConfigInitialized has copy, drop {
    config_id: ID,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    multisig_address: address,
}

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

// Share multisig config object and transfer multisig admin cap to publisher
fun init(ctx: &mut TxContext) {
    let multisig_config = MultisigConfig {
        id: object::new(ctx),
        public_keys: vector::empty(),
        weights: vector::empty(),
        threshold: 0,
        initialized: false,
    };
    let multisig_admin_cap = MultisigAdminCap {
        id: object::new(ctx),
    };

    transfer::share_object(multisig_config);
    transfer::transfer(multisig_admin_cap, ctx.sender());
}

// === Public-Mutative Functions ===
/// Multisig config can be initialized only once. `update_multisig_config` should be used for subsequent updates
public fun initialize_multisig_config(
    config: &mut MultisigConfig,
    _admin_cap: &MultisigAdminCap,
    public_keys: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
) {
    assert!(!config.initialized, EMultisigConfigAlreadyInitialized);
    assert!(public_keys.length() >= MIN_SIGNERS, ETooFewSigners);

    // Validates passed multisig parameters, aborting if they are invalid
    let multisig_address = multisig::derive_multisig_address_quiet(
        public_keys,
        weights,
        threshold,
    );

    config.public_keys = public_keys;
    config.weights = weights;
    config.threshold = threshold;
    config.initialized = true;

    event::emit(MultisigConfigInitialized {
        config_id: config.id.to_inner(),
        public_keys,
        weights,
        threshold,
        multisig_address,
    });
}

/// Multisig config can be updated only after it has been initialized by `initialize_multisig_config`
public fun update_multisig_config(
    config: &mut MultisigConfig,
    _admin: &MultisigAdminCap,
    new_public_keys: vector<vector<u8>>,
    new_weights: vector<u8>,
    new_threshold: u16,
) {
    assert!(config.initialized, EMultisigConfigNotInitialized);
    assert!(new_public_keys.length() >= MIN_SIGNERS, ETooFewSigners);

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

// === Public-Package Functions ===
public(package) fun validate_sender_is_admin_multisig(
    config: &MultisigConfig,
    ctx: &mut TxContext,
) {
    assert!(config.initialized, EMultisigConfigNotInitialized);
    assert!(
        multisig::check_if_sender_is_multisig_address(
            config.public_keys,
            config.weights,
            config.threshold,
            ctx,
        ),
        ESenderIsNotValidMultisig,
    );
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx); }

#[test_only]
public fun get_multisig_admin_cap_for_testing(ctx: &mut TxContext): MultisigAdminCap {
    MultisigAdminCap { id: object::new(ctx) }
}

#[test_only]
public fun get_multisig_config_params(
    config: &MultisigConfig,
): (vector<vector<u8>>, vector<u8>, u16) {
    (config.public_keys, config.weights, config.threshold)
}

#[test_only]
public fun unwrap_multisig_config_updated_event(
    event: &MultisigConfigUpdated,
): (
    ID,
    vector<vector<u8>>,
    vector<vector<u8>>,
    vector<u8>,
    vector<u8>,
    u16,
    u16,
    address,
    address,
) {
    (
        event.config_id,
        event.old_public_keys,
        event.new_public_keys,
        event.old_weights,
        event.new_weights,
        event.old_threshold,
        event.new_threshold,
        event.old_address,
        event.new_address,
    )
}

#[test_only]
public fun unwrap_multisig_config_initialized_event(
    event: &MultisigConfigInitialized,
): (ID, vector<vector<u8>>, vector<u8>, u16, address) {
    (event.config_id, event.public_keys, event.weights, event.threshold, event.multisig_address)
}
