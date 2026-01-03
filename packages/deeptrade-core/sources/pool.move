module deeptrade_core::dt_pool;

use deepbook::constants;
use deepbook::pool;
use deepbook::registry::Registry;
use deeptrade_core::ticket::{
    AdminTicket,
    update_pool_creation_protocol_fee_ticket_type,
    validate_ticket,
    destroy_ticket
};
use deeptrade_core::treasury::{Treasury, join_protocol_fee};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use token::deep::DEEP;

// === Errors ===
/// Error when the user has not enough DEEP to cover the deepbook and protocol fees
const ENotEnoughFee: u64 = 1;
/// Error when the new protocol fee for pool creation is out of the allowed range
const EPoolCreationFeeOutOfRange: u64 = 2;
// Error when the user provided fee is larger than the creation fee
const ECreationFeeTooLarge: u64 = 3;

// === Constants ===
const DEEP_SCALING_FACTOR: u64 = 1_000_000;
// Default protocol fee for creating a pool
const DEFAULT_POOL_CREATION_PROTOCOL_FEE: u64 = 100 * DEEP_SCALING_FACTOR; // 100 DEEP
// Maximum protocol fee for creating a pool
const MAX_POOL_CREATION_PROTOCOL_FEE: u64 = 500 * DEEP_SCALING_FACTOR; // 500 DEEP

// === Structs ===
/// Pool creation configuration object that stores the protocol fee
public struct PoolCreationConfig has key, store {
    id: UID,
    // Protocol fee can be updated by the admin
    protocol_fee: u64,
}

// === Events ===
/// Event emitted when a pool is created
public struct PoolCreated<phantom BaseAsset, phantom QuoteAsset> has copy, drop {
    config_id: ID,
    pool_id: ID,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
}

/// Event emitted when the protocol fee for creating a pool is updated
public struct PoolCreationProtocolFeeUpdated has copy, drop {
    config_id: ID,
    old_fee: u64,
    new_fee: u64,
}

/// Initialize the pool creation config object
fun init(ctx: &mut TxContext) {
    let config = PoolCreationConfig {
        id: object::new(ctx),
        protocol_fee: DEFAULT_POOL_CREATION_PROTOCOL_FEE,
    };

    transfer::share_object(config);
}

// === Public-Mutative Functions ===
/// Creates a new permissionless pool for trading between BaseAsset and QuoteAsset
/// Collects both DeepBook creation fee and protocol fee in DEEP coins
///
/// Parameters:
/// - treasury: Main treasury object that will receive the protocol fee
/// - config: Configuration object containing protocol fee information
/// - registry: DeepBook registry to create the pool in
/// - tick_size: Minimum price increment in the pool
/// - lot_size: Minimum quantity increment in the pool
/// - min_size: Minimum quantity of base asset required to create an order
/// - creation_fee: DEEP coins to pay for pool creation (both DeepBook and protocol fees)
/// - ctx: Transaction context
///
/// Flow:
/// 1. Calculates required fees (DeepBook fee + protocol fee)
/// 2. Verifies user has enough DEEP to cover all fees
/// 3. Splits the payment into DeepBook fee and protocol fee
/// 4. Adds protocol fee to the treasury
/// 5. Creates the permissionless pool in DeepBook
///
/// Returns:
/// - ID of the newly created pool
///
/// Aborts:
/// - ENotEnoughFee: If user doesn't provide enough DEEP to cover all fees
public fun create_permissionless_pool<BaseAsset, QuoteAsset>(
    treasury: &mut Treasury,
    config: &PoolCreationConfig,
    registry: &mut Registry,
    mut creation_fee: Coin<DEEP>,
    tick_size: u64,
    lot_size: u64,
    min_size: u64,
    ctx: &mut TxContext,
): ID {
    treasury.verify_version();

    let deepbook_fee = constants::pool_creation_fee();
    let protocol_fee = config.protocol_fee;
    let total_fee = deepbook_fee + protocol_fee;
    assert!(creation_fee.value() >= total_fee, ENotEnoughFee);
    // This explicit check just for improving dev experience
    assert!(creation_fee.value() <= total_fee, ECreationFeeTooLarge);

    // Take the fee coins from the creation fee
    let deepbook_fee_coin = creation_fee.split(deepbook_fee, ctx);
    let protocol_fee_coin = creation_fee.split(protocol_fee, ctx);

    // Move protocol fee to the treasury
    join_protocol_fee(treasury, protocol_fee_coin.into_balance());

    // Create the permissionless pool
    let pool_id = pool::create_permissionless_pool<BaseAsset, QuoteAsset>(
        registry,
        tick_size,
        lot_size,
        min_size,
        deepbook_fee_coin,
        ctx,
    );

    // Emit event for the newly created pool
    event::emit(PoolCreated<BaseAsset, QuoteAsset> {
        config_id: config.id.to_inner(),
        pool_id,
        tick_size,
        lot_size,
        min_size,
    });

    creation_fee.destroy_zero();

    pool_id
}

/// Update the protocol fee for creating a pool
/// Performs timelock validation using an admin ticket
///
/// Parameters:
/// - config: Pool creation configuration object
/// - ticket: Admin ticket for timelock validation (consumed on execution)
/// - new_fee: The new fee for creating a pool
/// - clock: Clock for timestamp validation
/// - ctx: Mutable transaction context for sender verification
///
/// Aborts:
/// - With ticket-related errors if ticket is invalid, expired, not ready, or wrong type
public fun update_pool_creation_protocol_fee(
    config: &mut PoolCreationConfig,
    ticket: AdminTicket,
    new_fee: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(new_fee <= MAX_POOL_CREATION_PROTOCOL_FEE, EPoolCreationFeeOutOfRange);

    validate_ticket(&ticket, update_pool_creation_protocol_fee_ticket_type(), clock, ctx);
    destroy_ticket(ticket, clock);

    let old_fee = config.protocol_fee;
    config.protocol_fee = new_fee;

    event::emit(PoolCreationProtocolFeeUpdated {
        config_id: config.id.to_inner(),
        old_fee,
        new_fee,
    });
}

// === Public-View Functions ===
/// Get the current protocol fee for creating a pool
public fun pool_creation_protocol_fee(config: &PoolCreationConfig): u64 { config.protocol_fee }

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

/// Get the default protocol fee for creating a pool
#[test_only]
public fun default_pool_creation_protocol_fee(): u64 {
    DEFAULT_POOL_CREATION_PROTOCOL_FEE
}

#[test_only]
public fun unwrap_pool_created_event<BaseAsset, QuoteAsset>(
    event: &PoolCreated<BaseAsset, QuoteAsset>,
): (ID, ID, u64, u64, u64) {
    (event.config_id, event.pool_id, event.tick_size, event.lot_size, event.min_size)
}

#[test_only]
public fun unwrap_pool_creation_protocol_fee_updated_event(
    event: &PoolCreationProtocolFeeUpdated,
): (ID, u64, u64) {
    (event.config_id, event.old_fee, event.new_fee)
}
