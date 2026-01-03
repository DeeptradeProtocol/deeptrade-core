module deeptrade_core::fee_manager;

use deepbook::balance_manager::BalanceManager;
use deepbook::constants::{live, partially_filled};
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deeptrade_core::admin::AdminCap;
use deeptrade_core::dt_math as math;
use deeptrade_core::multisig_config::MultisigConfig;
use deeptrade_core::treasury::{Treasury, join_protocol_fee};
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===
/// Error when the caller is not the owner of the fee manager
const EInvalidOwner: u64 = 1;
const EOrderNotLiveOrPartiallyFilled: u64 = 2;
const EOrderFullyExecuted: u64 = 3;
/// Error when trying to add a user unsettled fee with zero value
const EZeroUserUnsettledFee: u64 = 4;
/// Error when the order already has a user unsettled fee
const EUserUnsettledFeeAlreadyExists: u64 = 5;
/// Error when the maker quantity is zero on settling user fees
const EZeroMakerQuantity: u64 = 6;
/// Error when the filled quantity is greater than the original order quantity on settling user fees
const EFilledQuantityGreaterThanOrderQuantity: u64 = 7;
/// Error when the user unsettled fee is not empty to be destroyed
const EUserUnsettledFeeNotEmpty: u64 = 8;
const EProtocolUnsettledFeeNotEmpty: u64 = 9;
const EInvalidFeeManagerShareTicket: u64 = 10;

// === Structs ===
/// A shared object that manages a user's fee-related operations. Required for trading
public struct FeeManager has key {
    id: UID,
    owner: address,
    user_unsettled_fees: Bag,
    protocol_unsettled_fees: Bag,
}

/// A capability object that links a user to their `FeeManager`.
/// This object is owned by the user, making their shared `FeeManager` discoverable.
/// It does not grant any special permissions but serves as a pointer to the `fee_manager_id`.
public struct FeeManagerOwnerCap has key, store {
    id: UID,
    fee_manager_id: ID,
}

/// Key for storing a `UserUnsettledFee` in the `user_unsettled_fees` bag
public struct UserUnsettledFeeKey has copy, drop, store {
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
}

/// Key for storing the protocol's unsettled fee `Balance` in the `protocol_unsettled_fees` bag
public struct ProtocolUnsettledFeeKey<phantom CoinType> has copy, drop, store {}

/// Holds an order's unsettled maker fee
/// See `docs/unsettled-fees.md` for a detailed explanation of the unsettled fees system
public struct UserUnsettledFee<phantom CoinType> has store {
    /// Fee balance
    balance: Balance<CoinType>,
    order_quantity: u64,
    /// Maker quantity this fee balance corresponds to
    maker_quantity: u64,
}

/// A temporary receipt for aggregating fee settlement results during a batch process
public struct FeeSettlementReceipt<phantom FeeCoinType> {
    orders_count: u64,
    total_fees_settled: u64,
}

/// A hot potato object ensuring a newly created `FeeManager` is shared. It is returned by `new`
/// and must be consumed by the corresponding share function
public struct FeeManagerShareTicket { fee_manager_id: ID }

// === Events ===
public struct UserUnsettledFeeAdded<phantom CoinType> has copy, drop {
    key: UserUnsettledFeeKey,
    unsettled_fee_value: u64,
    order_quantity: u64,
    maker_quantity: u64,
}

public struct UserFeesSettled<phantom CoinType> has copy, drop {
    key: UserUnsettledFeeKey,
    returned_to_user: u64,
    paid_to_protocol: u64,
    order_quantity: u64,
    maker_quantity: u64,
    filled_quantity: u64,
}

public struct ProtocolFeesSettled<phantom FeeCoinType> has copy, drop {
    orders_count: u64,
    total_fees_settled: u64,
}

public struct FeeManagerCreated has copy, drop {
    fee_manager_id: ID,
    fee_manager_owner_cap_id: ID,
    owner: address,
}

// === Public-Mutative Functions ===
/// Creates an unshared `FeeManager`, `FeeManagerOwnerCap`, and `FeeManagerShareTicket`.
/// The manager and ticket must be passed to `share_fee_manager` to finalize creation and enforce
/// the object sharing policy.
public fun new(ctx: &mut TxContext): (FeeManager, FeeManagerOwnerCap, FeeManagerShareTicket) {
    let owner = ctx.sender();

    let fee_manager_uid = object::new(ctx);
    let fee_manager_owner_cap_uid = object::new(ctx);
    let fee_manager_id = fee_manager_uid.to_inner();
    let fee_manager_owner_cap_id = fee_manager_owner_cap_uid.to_inner();

    let owner_cap = FeeManagerOwnerCap {
        id: fee_manager_owner_cap_uid,
        fee_manager_id,
    };

    let fee_manager = FeeManager {
        id: fee_manager_uid,
        owner,
        user_unsettled_fees: bag::new(ctx),
        protocol_unsettled_fees: bag::new(ctx),
    };

    let ticket = FeeManagerShareTicket {
        fee_manager_id,
    };

    event::emit(FeeManagerCreated {
        fee_manager_id,
        fee_manager_owner_cap_id,
        owner,
    });

    (fee_manager, owner_cap, ticket)
}

/// Shares the `FeeManager` object, consuming the `FeeManagerShareTicket` to enforce the policy
public fun share_fee_manager(fee_manager: FeeManager, ticket: FeeManagerShareTicket) {
    assert!(fee_manager.id.to_inner() == ticket.fee_manager_id, EInvalidFeeManagerShareTicket);

    let FeeManagerShareTicket { .. } = ticket;
    transfer::share_object(fee_manager);
}

/// Creates a `FeeSettlementReceipt` to begin a batch fee settlement process
public fun start_protocol_fee_settlement<FeeCoinType>(): FeeSettlementReceipt<FeeCoinType> {
    FeeSettlementReceipt {
        orders_count: 0,
        total_fees_settled: 0,
    }
}

/// Settles a filled order's fee by transferring it to the protocol, recording it in a `FeeSettlementReceipt`.
///
/// This is a permissionless function for collecting fees from completed orders. The fee object is
/// left empty to allow the user to claim a storage rebate. Does nothing if the order is still live
/// or has no unsettled fee.
public fun settle_filled_order_fee_and_record<BaseToken, QuoteToken, FeeCoinType>(
    treasury: &mut Treasury,
    fee_manager: &mut FeeManager,
    receipt: &mut FeeSettlementReceipt<FeeCoinType>,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
) {
    treasury.verify_version();

    let open_orders = pool.account_open_orders(balance_manager);

    // Don't settle fees to protocol while the order is live
    if (open_orders.contains(&order_id)) return;

    let filled_order_fee_key = UserUnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    // No unsettled fee exists if the fee was already settled or never added
    if (!fee_manager.user_unsettled_fees.contains(filled_order_fee_key)) return;

    // We borrow the object to leave it empty, so the user can later claim a storage rebate
    // via `claim_user_unsettled_fee_storage_rebate`
    let filled_order_fee: &mut UserUnsettledFee<FeeCoinType> = fee_manager
        .user_unsettled_fees
        .borrow_mut(filled_order_fee_key);
    let filled_order_fee_balance = filled_order_fee.balance.withdraw_all();

    // Update receipt with settled fee details
    let settled_amount = filled_order_fee_balance.value();
    if (settled_amount > 0) {
        receipt.orders_count = receipt.orders_count + 1;
        receipt.total_fees_settled = receipt.total_fees_settled + settled_amount;
    };

    treasury.join_protocol_fee(filled_order_fee_balance);
}

/// Settles aggregated protocol fees for a coin type, transferring them to the treasury.
///
/// This is a permissionless function that records the result in a `FeeSettlementReceipt`.
/// The fee balance is left empty to allow a storage rebate claim. Does nothing if no fee
/// is found for the given coin type.
public fun settle_protocol_fee_and_record<FeeCoinType>(
    treasury: &mut Treasury,
    fee_manager: &mut FeeManager,
    receipt: &mut FeeSettlementReceipt<FeeCoinType>,
) {
    treasury.verify_version();

    let protocol_unsettled_fee_key = ProtocolUnsettledFeeKey<FeeCoinType> {};
    if (!fee_manager.protocol_unsettled_fees.contains(protocol_unsettled_fee_key)) return;

    // We borrow the object to leave it empty, so the user can later claim a storage rebate
    // via `claim_protocol_unsettled_fee_storage_rebate`
    let protocol_unsettled_fee: &mut Balance<FeeCoinType> = fee_manager
        .protocol_unsettled_fees
        .borrow_mut(protocol_unsettled_fee_key);
    let protocol_unsettled_fee_balance = protocol_unsettled_fee.withdraw_all();

    // Update receipt with settled fee details
    let settled_amount = protocol_unsettled_fee_balance.value();
    if (settled_amount > 0) {
        receipt.total_fees_settled = receipt.total_fees_settled + settled_amount;
    };

    treasury.join_protocol_fee(protocol_unsettled_fee_balance);
}

/// Finalizes a batch fee settlement, emitting an event with the total settled amount
public fun finish_protocol_fee_settlement<FeeCoinType>(receipt: FeeSettlementReceipt<FeeCoinType>) {
    if (receipt.total_fees_settled > 0) {
        event::emit(ProtocolFeesSettled<FeeCoinType> {
            orders_count: receipt.orders_count,
            total_fees_settled: receipt.total_fees_settled,
        });
    };

    // Destroy the receipt object
    let FeeSettlementReceipt { .. } = receipt;
}

/// Claims the storage rebate for a settled user fee by destroying the empty fee object.
///
/// Can only be called by the `FeeManager` owner after a fee has been collected via
/// `settle_filled_order_fee_and_record`. Aborts if the fee object is not empty.
public fun claim_user_unsettled_fee_storage_rebate<BaseToken, QuoteToken, FeeCoinType>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
    ctx: &mut TxContext,
) {
    treasury.verify_version();
    fee_manager.validate_owner(ctx);

    claim_user_unsettled_fee_rebate_core<BaseToken, QuoteToken, FeeCoinType>(
        fee_manager,
        pool,
        balance_manager,
        order_id,
    );
}

/// Allows a protocol admin to claim a user's unsettled fee storage rebate.
///
/// This is a protected maintenance function to clean up empty fee objects that users have
/// not claimed. Aborts if the fee object is not empty.
public fun claim_user_unsettled_fee_storage_rebate_admin<BaseToken, QuoteToken, FeeCoinType>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    order_id: u128,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);
    treasury.verify_version();

    claim_user_unsettled_fee_rebate_core<BaseToken, QuoteToken, FeeCoinType>(
        fee_manager,
        pool,
        balance_manager,
        order_id,
    );
}

/// Claims the storage rebate for a settled protocol fee by destroying the empty balance.
///
/// Can only be called by the `FeeManager` owner after a fee has been collected via
/// `settle_protocol_fee_and_record`. Aborts if the balance is not empty.
public fun claim_protocol_unsettled_fee_storage_rebate<FeeCoinType>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    ctx: &mut TxContext,
) {
    treasury.verify_version();
    fee_manager.validate_owner(ctx);

    claim_protocol_unsettled_fee_rebate_core<FeeCoinType>(fee_manager);
}

/// Allows a protocol admin to claim a protocol unsettled fee storage rebate.
///
/// This is a protected maintenance function to clean up empty fee balances that have not
/// been claimed. Aborts if the balance is not empty.
public fun claim_protocol_unsettled_fee_storage_rebate_admin<FeeCoinType>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);
    treasury.verify_version();

    claim_protocol_unsettled_fee_rebate_core<FeeCoinType>(fee_manager);
}

// === Public-Package Functions ===
/// Stores the potential maker fee for a new limit order in a `UserUnsettledFee` object.
///
/// This fee is linked to the live order and settled later. Aborts if the order is invalid
/// (e.g., not live, zero fee) or if an unsettled fee already exists for it.
public(package) fun add_to_user_unsettled_fees<CoinType>(
    fee_manager: &mut FeeManager,
    fee: Balance<CoinType>,
    order_info: &OrderInfo,
    ctx: &TxContext,
) {
    fee_manager.validate_owner(ctx);

    // Order must be live or partially filled to have unsettled fee
    let order_status = order_info.status();
    assert!(
        order_status == live() || order_status == partially_filled(),
        EOrderNotLiveOrPartiallyFilled,
    );

    // Sanity check: order must not be fully executed to have an unsettled fee. If the order is
    // fully executed but still has live or partially filled status, there's an error in DeepBook logic.
    let order_quantity = order_info.original_quantity();
    let executed_quantity = order_info.executed_quantity();
    assert!(executed_quantity < order_quantity, EOrderFullyExecuted);

    // Fee must be not zero to be added
    let fee_value = fee.value();
    assert!(fee_value > 0, EZeroUserUnsettledFee);

    let user_unsettled_fee_key = UserUnsettledFeeKey {
        pool_id: order_info.pool_id(),
        balance_manager_id: order_info.balance_manager_id(),
        order_id: order_info.order_id(),
    };
    let maker_quantity = order_quantity - executed_quantity;

    // Verify the order doesn't have an unsettled fee yet
    // By design, we shouldn’t allow adding a user unsettled fee for a single order multiple times
    assert!(
        !fee_manager.user_unsettled_fees.contains(user_unsettled_fee_key),
        EUserUnsettledFeeAlreadyExists,
    );

    // Create the unsettled fee
    let user_unsettled_fee = UserUnsettledFee<CoinType> {
        balance: fee,
        order_quantity,
        maker_quantity,
    };
    fee_manager.user_unsettled_fees.add(user_unsettled_fee_key, user_unsettled_fee);

    event::emit(UserUnsettledFeeAdded<CoinType> {
        key: user_unsettled_fee_key,
        unsettled_fee_value: fee_value,
        order_quantity,
        maker_quantity,
    });
}

/// Adds a given fee to the protocol's unsettled fees bag, aggregating it with any existing
/// balance for the same coin type. This bag holds protocol-bound fees before they are
/// settled into the treasury by the `settle_protocol_fee_and_record` function.
///
/// In case zero `fee` is provided, the function will destroy the `fee` object and return.
/// This is done to avoid adding zero fees to the protocol's unsettled fees bag,
/// effectively reducing computation and storage gas cost.
///
/// This could be a case, when top-level function that uses this method,
/// charges zero protocol fees for the operation (for instance, swap protocol fees is 0 for a particular market).
///
/// The transaction will abort if the caller is not the owner of the `FeeManager`.
public(package) fun add_to_protocol_unsettled_fees<CoinType>(
    fee_manager: &mut FeeManager,
    fee: Balance<CoinType>,
    ctx: &TxContext,
) {
    fee_manager.validate_owner(ctx);

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ProtocolUnsettledFeeKey<CoinType> {};
    if (fee_manager.protocol_unsettled_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = fee_manager.protocol_unsettled_fees.borrow_mut(key);
        balance.join(fee);
    } else {
        fee_manager.protocol_unsettled_fees.add(key, fee);
    };
}

/// Settles a user's fee for an order during cancellation, splitting the fee between the user and protocol.
///
/// The fee for the unfilled portion is refunded to the user, while the fee for the filled portion
/// is paid to the protocol. Destroys the `UserUnsettledFee` object, granting a storage rebate to the caller.
///
/// Returns the user's refund as a `Coin`. Aborts on invalid owner or if the order was fully filled.
public(package) fun settle_user_fees<BaseToken, QuoteToken, FeeCoinType>(
    fee_manager: &mut FeeManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
    ctx: &mut TxContext,
): Coin<FeeCoinType> {
    fee_manager.validate_owner(ctx);

    let user_unsettled_fee_key = UserUnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    // No unsettled fee exists if the fee was already settled or never added
    if (!fee_manager.user_unsettled_fees.contains(user_unsettled_fee_key)) return coin::zero(ctx);

    let mut user_unsettled_fee: UserUnsettledFee<FeeCoinType> = fee_manager
        .user_unsettled_fees
        .remove(user_unsettled_fee_key);
    let user_unsettled_fee_value = user_unsettled_fee.balance.value();
    let order = pool.get_order(order_id);
    let order_quantity = user_unsettled_fee.order_quantity;
    let maker_quantity = user_unsettled_fee.maker_quantity;
    let filled_quantity = order.filled_quantity();

    // Sanity check: maker quantity must be greater than zero. If it's zero, the unsettled fee
    // should not have been added. We validate this during fee addition, so this should never occur.
    assert!(maker_quantity > 0, EZeroMakerQuantity);
    // Sanity check: filled quantity must be less than total order quantity. If they are equal,
    // the order is fully executed and the `pool.get_order` call above should abort. If filled
    // quantity exceeds total order quantity, there's an error in either the unsettled fees
    // mechanism or DeepBook's order filling logic.
    assert!(filled_quantity < order_quantity, EFilledQuantityGreaterThanOrderQuantity);

    let return_to_user = if (filled_quantity == 0) {
        // If the order is completely unfilled, return all fees
        user_unsettled_fee_value
    } else {
        let not_executed_quantity = order_quantity - filled_quantity;
        math::mul_div(
            user_unsettled_fee_value,
            not_executed_quantity,
            maker_quantity,
        )
    };
    let pay_to_protocol = user_unsettled_fee_value - return_to_user;

    let return_to_user_balance = user_unsettled_fee.balance.split(return_to_user);
    if (pay_to_protocol > 0)
        fee_manager.add_to_protocol_unsettled_fees<FeeCoinType>(
            user_unsettled_fee.balance.split(pay_to_protocol),
            ctx,
        );

    // The unsettled fee balance must now be zero, as the full amount has been split between
    // the portion returned to the user and the portion paid to the protocol.
    user_unsettled_fee.destroy_empty();

    event::emit(UserFeesSettled<FeeCoinType> {
        key: user_unsettled_fee_key,
        returned_to_user: return_to_user,
        paid_to_protocol: pay_to_protocol,
        order_quantity,
        maker_quantity,
        filled_quantity,
    });

    return_to_user_balance.into_coin(ctx)
}

// === Private Functions ===
/// Destroy the empty unsettled fee
fun destroy_empty<CoinType>(user_unsettled_fee: UserUnsettledFee<CoinType>) {
    assert!(user_unsettled_fee.balance.value() == 0, EUserUnsettledFeeNotEmpty);

    let UserUnsettledFee { balance, .. } = user_unsettled_fee;
    balance.destroy_zero();
}

/// Core logic for claiming the storage rebate for a user's unsettled fee
fun claim_user_unsettled_fee_rebate_core<BaseToken, QuoteToken, FeeCoinType>(
    fee_manager: &mut FeeManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
) {
    let user_unsettled_fee_key = UserUnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!fee_manager.user_unsettled_fees.contains(user_unsettled_fee_key)) return;

    let user_unsettled_fee: UserUnsettledFee<FeeCoinType> = fee_manager
        .user_unsettled_fees
        .remove(user_unsettled_fee_key);

    user_unsettled_fee.destroy_empty();
}

/// Core logic for claiming the storage rebate for a protocol's unsettled fee
fun claim_protocol_unsettled_fee_rebate_core<FeeCoinType>(fee_manager: &mut FeeManager) {
    let protocol_unsettled_fee_key = ProtocolUnsettledFeeKey<FeeCoinType> {};

    if (!fee_manager.protocol_unsettled_fees.contains(protocol_unsettled_fee_key)) return;

    let protocol_unsettled_fee: Balance<FeeCoinType> = fee_manager
        .protocol_unsettled_fees
        .remove(protocol_unsettled_fee_key);

    assert!(protocol_unsettled_fee.value() == 0, EProtocolUnsettledFeeNotEmpty);

    protocol_unsettled_fee.destroy_zero();
}

/// Validates that the transaction sender is the owner of the `FeeManager`. Aborts if not
fun validate_owner(fee_manager: &FeeManager, ctx: &TxContext) {
    assert!(ctx.sender() == fee_manager.owner, EInvalidOwner);
}

// === Test Functions ===
/// Check if an unsettled fee exists for a specific order
#[test_only]
public fun has_user_unsettled_fee(
    fee_manager: &FeeManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): bool {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    fee_manager.user_unsettled_fees.contains(key)
}

/// Get the unsettled fee balance for a specific order
#[test_only]
public fun get_user_unsettled_fee_balance<CoinType>(
    fee_manager: &FeeManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): u64 {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let user_unsettled_fee: &UserUnsettledFee<CoinType> = fee_manager
        .user_unsettled_fees
        .borrow(key);
    user_unsettled_fee.balance.value()
}

/// Get the order parameters stored in an unsettled fee
#[test_only]
public fun get_user_unsettled_fee_order_params<CoinType>(
    fee_manager: &FeeManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): (u64, u64) {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let user_unsettled_fee: &UserUnsettledFee<CoinType> = fee_manager
        .user_unsettled_fees
        .borrow(key);
    (user_unsettled_fee.order_quantity, user_unsettled_fee.maker_quantity)
}

/// Check if a protocol's unsettled fee exists for a specific coin type
#[test_only]
public fun has_protocol_unsettled_fee<FeeCoinType>(fee_manager: &FeeManager): bool {
    let key = ProtocolUnsettledFeeKey<FeeCoinType> {};
    fee_manager.protocol_unsettled_fees.contains(key)
}

/// Get the protocol's unsettled fee balance for a specific coin type
#[test_only]
public fun get_protocol_unsettled_fee_balance<FeeCoinType>(fee_manager: &FeeManager): u64 {
    let key = ProtocolUnsettledFeeKey<FeeCoinType> {};
    let protocol_unsettled_fee: &Balance<FeeCoinType> = fee_manager
        .protocol_unsettled_fees
        .borrow(key);
    protocol_unsettled_fee.value()
}

/// Finalize the protocol fee settlement process and return the result for testing
#[test_only]
public fun finish_protocol_fee_settlement_for_testing<FeeCoinType>(
    receipt: FeeSettlementReceipt<FeeCoinType>,
): (u64, u64) {
    let count = receipt.orders_count;
    let total = receipt.total_fees_settled;
    finish_protocol_fee_settlement(receipt);
    (count, total)
}
