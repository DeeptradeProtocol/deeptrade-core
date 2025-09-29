module deeptrade_core::treasury;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::helper::current_version;
use deeptrade_core::multisig_config::MultisigConfig;
use deeptrade_core::ticket::{
    AdminTicket,
    validate_ticket,
    destroy_ticket,
    withdraw_coverage_fee_ticket_type,
    withdraw_protocol_fee_ticket_type,
    withdraw_deep_reserves_ticket_type
};
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;
use sui::vec_set::{Self, VecSet};
use token::deep::DEEP;

// === Errors ===
/// Error when trying to use deep from reserves but there is not enough available
const EInsufficientDeepReserves: u64 = 1;
/// Allowed versions management errors
const EVersionAlreadyEnabled: u64 = 2;
const ECannotDisableNewerVersion: u64 = 3;
const EVersionNotEnabled: u64 = 4;
/// Error when trying to use shared object in a package whose version is not enabled
const EPackageVersionNotEnabled: u64 = 5;

/// Error when trying to enable a version that has been permanently disabled
const EVersionPermanentlyDisabled: u64 = 6;

// === Structs ===
public struct Treasury has key, store {
    id: UID,
    allowed_versions: VecSet<u16>,
    // Permanently disabled package versions
    disabled_versions: VecSet<u16>,
    deep_reserves: Balance<DEEP>,
    deep_reserves_coverage_fees: Bag,
    protocol_fees: Bag,
}

/// Key struct for storing charged fees by coin type
public struct ChargedFeeKey<phantom CoinType> has copy, drop, store {}

// === Events ===
/// Event emitted when DEEP coins are withdrawn from the treasury's reserves
public struct DeepReservesWithdrawn<phantom DEEP> has copy, drop {
    treasury_id: ID,
    amount: u64,
}

/// Event emitted when deep reserves coverage fees are withdrawn for a specific coin type
public struct CoverageFeeWithdrawn<phantom CoinType> has copy, drop {
    treasury_id: ID,
    amount: u64,
}

/// Event emitted when protocol fees are withdrawn for a specific coin type
public struct ProtocolFeeWithdrawn<phantom CoinType> has copy, drop {
    treasury_id: ID,
    amount: u64,
}

/// Event emitted when DEEP coins are deposited into the treasury's reserves
public struct DeepReservesDeposited<phantom DEEP> has copy, drop {
    treasury_id: ID,
    amount: u64,
}

/// Event emitted when a new version is enabled for the treasury
public struct VersionEnabled has copy, drop {
    treasury_id: ID,
    version: u16,
}

/// Event emitted when a version is permanently disabled for the treasury
public struct VersionDisabled has copy, drop {
    treasury_id: ID,
    version: u16,
}

fun init(ctx: &mut TxContext) {
    let treasury = Treasury {
        id: object::new(ctx),
        allowed_versions: vec_set::singleton(current_version()),
        disabled_versions: vec_set::empty(),
        deep_reserves: balance::zero(),
        deep_reserves_coverage_fees: bag::new(ctx),
        protocol_fees: bag::new(ctx),
    };

    transfer::share_object(treasury);
}

// === Public-Mutative Functions ===
/// Deposit DEEP coins into the treasury's reserves
public fun deposit_into_reserves(treasury: &mut Treasury, deep_coin: Coin<DEEP>) {
    treasury.verify_version();

    if (deep_coin.value() == 0) {
        deep_coin.destroy_zero();
        return
    };

    event::emit(DeepReservesDeposited<DEEP> {
        treasury_id: treasury.id.to_inner(),
        amount: deep_coin.value(),
    });

    treasury.deep_reserves.join(deep_coin.into_balance());
}

/// Withdraw deep reserves coverage fees for a specific coin type
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - treasury: Treasury object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All coverage fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_coverage_fee<CoinType>(
    treasury: &mut Treasury,
    ticket: AdminTicket,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    treasury.verify_version();
    validate_ticket(&ticket, withdraw_coverage_fee_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let key = ChargedFeeKey<CoinType> {};

    if (treasury.deep_reserves_coverage_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = treasury.deep_reserves_coverage_fees.borrow_mut(key);
        let coin = balance.withdraw_all().into_coin(ctx);

        event::emit(CoverageFeeWithdrawn<CoinType> {
            treasury_id: treasury.id.to_inner(),
            amount: coin.value(),
        });

        coin
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw protocol fees for a specific coin type
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - treasury: Treasury object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<CoinType>: All protocol fees of the specified type, or zero coin if none exist
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_protocol_fee<CoinType>(
    treasury: &mut Treasury,
    ticket: AdminTicket,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<CoinType> {
    treasury.verify_version();
    validate_ticket(&ticket, withdraw_protocol_fee_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let key = ChargedFeeKey<CoinType> {};

    if (treasury.protocol_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = treasury.protocol_fees.borrow_mut(key);
        let coin = balance.withdraw_all().into_coin(ctx);

        event::emit(ProtocolFeeWithdrawn<CoinType> {
            treasury_id: treasury.id.to_inner(),
            amount: coin.value(),
        });

        coin
    } else {
        coin::zero(ctx)
    }
}

/// Withdraw a specified amount of DEEP coins from the treasury's reserves
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - treasury: Treasury object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - amount: Amount of DEEP tokens to withdraw
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for coin creation and sender verification
///
/// Returns:
/// - Coin<DEEP>: The requested amount of DEEP tokens withdrawn from reserves
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun withdraw_deep_reserves(
    treasury: &mut Treasury,
    ticket: AdminTicket,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<DEEP> {
    treasury.verify_version();
    validate_ticket(&ticket, withdraw_deep_reserves_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let coin = split_deep_reserves(treasury, amount, ctx);

    event::emit(DeepReservesWithdrawn<DEEP> {
        treasury_id: treasury.id.to_inner(),
        amount,
    });

    coin
}

/// Enable the specified package version for the treasury
///
/// Parameters:
/// - treasury: Treasury object
/// - multisig_config: Protocol's admin multisig config
/// - _admin: Admin capability
/// - version: Package version to enable
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ESenderIsNotValidMultisig if the transaction sender is not the protocol's admin multisig
/// - With EVersionAlreadyEnabled if the version is already enabled
public fun enable_version(
    treasury: &mut Treasury,
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    version: u16,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);

    // Check if the version has been permanently disabled
    assert!(!treasury.disabled_versions.contains(&version), EVersionPermanentlyDisabled);

    // Check if the version is already enabled
    assert!(!treasury.allowed_versions.contains(&version), EVersionAlreadyEnabled);

    treasury.allowed_versions.insert(version);

    event::emit(VersionEnabled {
        treasury_id: treasury.id.to_inner(),
        version,
    });
}

/// Permanently disable the specified package version for the treasury
///
/// Parameters:
/// - treasury: Treasury object
/// - multisig_config: Protocol's admin multisig config
/// - _admin: Admin capability
/// - version: Package version to disable
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ESenderIsNotValidMultisig if the transaction sender is not the protocol's admin multisig
/// - With ECannotDisableNewerVersion if trying to disable a newer version
/// - With EVersionNotEnabled if the version is not currently enabled
public fun disable_version(
    treasury: &mut Treasury,
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    version: u16,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);
    assert!(version <= current_version(), ECannotDisableNewerVersion);
    assert!(treasury.allowed_versions.contains(&version), EVersionNotEnabled);

    // Remove from allowed and add to disabled
    treasury.allowed_versions.remove(&version);
    treasury.disabled_versions.insert(version);

    event::emit(VersionDisabled {
        treasury_id: treasury.id.to_inner(),
        version,
    });
}

// === Public-View Functions ===
/// Get the value of DEEP in the reserves
public fun deep_reserves(treasury: &Treasury): u64 { treasury.deep_reserves.value() }

// === Public-Package Functions ===
/// Add collected deep reserves coverage fees to the treasury's fee storage
public(package) fun join_coverage_fee<CoinType>(treasury: &mut Treasury, fee: Balance<CoinType>) {
    treasury.verify_version();

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ChargedFeeKey<CoinType> {};
    if (treasury.deep_reserves_coverage_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = treasury.deep_reserves_coverage_fees.borrow_mut(key);
        balance.join(fee);
    } else {
        treasury.deep_reserves_coverage_fees.add(key, fee);
    };
}

/// Add collected protocol fees to the treasury's fee storage
public(package) fun join_protocol_fee<CoinType>(treasury: &mut Treasury, fee: Balance<CoinType>) {
    treasury.verify_version();

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ChargedFeeKey<CoinType> {};
    if (treasury.protocol_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = treasury.protocol_fees.borrow_mut(key);
        balance.join(fee);
    } else {
        treasury.protocol_fees.add(key, fee);
    };
}

/// Get the splitted DEEP coin from the reserves
public(package) fun split_deep_reserves(
    treasury: &mut Treasury,
    amount: u64,
    ctx: &mut TxContext,
): Coin<DEEP> {
    treasury.verify_version();

    let available_deep_reserves = treasury.deep_reserves.value();
    assert!(amount <= available_deep_reserves, EInsufficientDeepReserves);

    treasury.deep_reserves.split(amount).into_coin(ctx)
}

/// Verify that the current package version is enabled in the treasury
public(package) fun verify_version(treasury: &Treasury) {
    let package_version = current_version();
    assert!(treasury.allowed_versions.contains(&package_version), EPackageVersionNotEnabled);
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun allowed_versions(treasury: &Treasury): &VecSet<u16> {
    &treasury.allowed_versions
}

#[test_only]
public fun disabled_versions(treasury: &Treasury): &VecSet<u16> {
    &treasury.disabled_versions
}

/// Get the deep reserves coverage fees bag for testing.
#[test_only]
public fun deep_reserves_coverage_fees(treasury: &Treasury): &Bag {
    &treasury.deep_reserves_coverage_fees
}

/// Get the deep reserves coverage fee balance for a specific coin type.
#[test_only]
public fun get_deep_reserves_coverage_fee_balance<CoinType>(treasury: &Treasury): u64 {
    let key = ChargedFeeKey<CoinType> {};
    if (treasury.deep_reserves_coverage_fees.contains(key)) {
        let balance: &Balance<CoinType> = treasury.deep_reserves_coverage_fees.borrow(key);
        balance.value()
    } else {
        0
    }
}

/// Get the protocol fees bag for testing.
#[test_only]
public fun protocol_fees(treasury: &Treasury): &Bag {
    &treasury.protocol_fees
}

/// Get the protocol fee balance for a specific coin type.
#[test_only]
public fun get_protocol_fee_balance<CoinType>(treasury: &Treasury): u64 {
    let key = ChargedFeeKey<CoinType> {};
    if (treasury.protocol_fees.contains(key)) {
        let balance: &Balance<CoinType> = treasury.protocol_fees.borrow(key);
        balance.value()
    } else {
        0
    }
}

#[test_only]
public fun unwrap_deep_reserves_withdrawn_event(event: &DeepReservesWithdrawn<DEEP>): (ID, u64) {
    (event.treasury_id, event.amount)
}

#[test_only]
public fun unwrap_coverage_fee_withdrawn_event<CoinType>(
    event: &CoverageFeeWithdrawn<CoinType>,
): (ID, u64) {
    (event.treasury_id, event.amount)
}

#[test_only]
public fun unwrap_protocol_fee_withdrawn_event<CoinType>(
    event: &ProtocolFeeWithdrawn<CoinType>,
): (ID, u64) {
    (event.treasury_id, event.amount)
}

#[test_only]
public fun unwrap_deep_reserves_deposited_event(event: &DeepReservesDeposited<DEEP>): (ID, u64) {
    (event.treasury_id, event.amount)
}

#[test_only]
public fun unwrap_version_enabled_event(event: &VersionEnabled): (ID, u16) {
    (event.treasury_id, event.version)
}

#[test_only]
public fun unwrap_version_disabled_event(event: &VersionDisabled): (ID, u16) {
    (event.treasury_id, event.version)
}

/// Check if deep reserves coverage fees exist for a specific coin type
#[test_only]
public fun has_deep_reserves_coverage_fee<CoinType>(treasury: &Treasury): bool {
    let key = ChargedFeeKey<CoinType> {};
    treasury.deep_reserves_coverage_fees.contains(key)
}
