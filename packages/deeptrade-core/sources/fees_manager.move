module deeptrade_core::fees_manager;

use deepbook::balance_manager::BalanceManager;
use deepbook::constants::{live, partially_filled};
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deeptrade_core::admin::AdminCap;
use deeptrade_core::math;
use deeptrade_core::treasury::{Treasury, join_protocol_fee};
use multisig::multisig;
use sui::bag::{Self, Bag};
use sui::balance::Balance;
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===
/// Error when the caller is not the owner of the balance manager
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
const ESenderIsNotMultisig: u64 = 10;

// === Structs ===
public struct FeesManager has key, store {
    id: UID,
    owner: address,
    user_unsettled_fees: Bag,
    protocol_unsettled_fees: Bag,
}

/// Key struct for storing unsettled fees by pool, balance manager, and order id
public struct UserUnsettledFeeKey has copy, drop, store {
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
}

public struct ProtocolUnsettledFeeKey<phantom CoinType> has copy, drop, store {}

/// Unsettled fee for specific order
/// See `docs/unsettled-fees.md` for detailed explanation of the unsettled fees system.
public struct UserUnsettledFee<phantom CoinType> has store {
    /// Fee balance
    balance: Balance<CoinType>,
    order_quantity: u64,
    /// Maker quantity this fee balance corresponds to
    maker_quantity: u64,
}

/// A temporary receipt for aggregating batch fee settlement results
public struct FeeSettlementReceipt<phantom FeeCoinType> {
    orders_count: u64,
    total_fees_settled: u64,
}

// === Events ===
public struct UserUnsettledFeeAdded<phantom CoinType> has copy, drop {
    key: UserUnsettledFeeKey,
    fee_value: u64,
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

public struct FeesManagerCreated has copy, drop {
    fees_manager_id: ID,
    owner: address,
}

// === Public-Mutative Functions ===
public fun new(ctx: &mut TxContext) {
    let id = object::new(ctx);
    let owner = ctx.sender();

    event::emit(FeesManagerCreated {
        fees_manager_id: id.to_inner(),
        owner,
    });

    let fees_manager = FeesManager {
        id,
        owner,
        user_unsettled_fees: bag::new(ctx),
        protocol_unsettled_fees: bag::new(ctx),
    };

    transfer::share_object(fees_manager);
}

/// Start the protocol fee settlement process for a specific coin by creating a FeeSettlementReceipt
public fun start_protocol_fee_settlement<FeeCoinType>(): FeeSettlementReceipt<FeeCoinType> {
    FeeSettlementReceipt {
        orders_count: 0,
        total_fees_settled: 0,
    }
}

/// Settles remaining unsettled fees to the protocol for orders that are no longer live
/// (i.e., cancelled or filled) and records the result in a `FeeSettlementReceipt`.
/// See `docs/unsettled-fees.md` for a detailed explanation of the unsettled fees system.
///
/// The function silently returns if:
/// - The order is still live (i.e., present in the account's open orders).
/// - No unsettled fees exist for the order.
public fun settle_filled_order_fee_and_record<BaseToken, QuoteToken, FeeCoinType>(
    treasury: &mut Treasury,
    fees_manager: &mut FeesManager,
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

    if (!fees_manager.user_unsettled_fees.contains(filled_order_fee_key)) return;

    let filled_order_fee: &mut UserUnsettledFee<FeeCoinType> = fees_manager
        .user_unsettled_fees
        .borrow_mut(filled_order_fee_key); // Borrow mut instead of remove to let user claim storage rebates
    let filled_order_fee_balance = filled_order_fee.balance.withdraw_all();

    // Update receipt with settled fee details
    let settled_amount = filled_order_fee_balance.value();
    if (settled_amount > 0) {
        receipt.orders_count = receipt.orders_count + 1;
        receipt.total_fees_settled = receipt.total_fees_settled + settled_amount;
    };

    treasury.join_protocol_fee(filled_order_fee_balance);
}

public fun settle_protocol_fee_and_record<FeeCoinType>(
    treasury: &mut Treasury,
    fees_manager: &mut FeesManager,
    receipt: &mut FeeSettlementReceipt<FeeCoinType>,
) {
    treasury.verify_version();

    let protocol_unsettled_fee_key = ProtocolUnsettledFeeKey<FeeCoinType> {};
    if (!fees_manager.protocol_unsettled_fees.contains(protocol_unsettled_fee_key)) return;

    let protocol_unsettled_fee: &mut Balance<FeeCoinType> = fees_manager
        .protocol_unsettled_fees
        .borrow_mut(protocol_unsettled_fee_key); // Borrow mut instead of remove to let user claim storage rebates
    let protocol_unsettled_fee_balance = protocol_unsettled_fee.withdraw_all();

    // Update receipt with settled fee details
    let settled_amount = protocol_unsettled_fee_balance.value();
    if (settled_amount > 0) {
        receipt.total_fees_settled = receipt.total_fees_settled + settled_amount;
    };

    treasury.join_protocol_fee(protocol_unsettled_fee_balance);
}

/// Finalize the protocol fee settlement process, emitting an event with the total settled amount
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

public fun claim_user_unsettled_fee_storage_rebate<BaseToken, QuoteToken, FeeCoinType>(
    fees_manager: &mut FeesManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
    ctx: &mut TxContext,
) {
    fees_manager.validate_owner(ctx);

    claim_user_unsettled_fee_rebates_core<BaseToken, QuoteToken, FeeCoinType>(
        fees_manager,
        pool,
        balance_manager,
        order_id,
    );
}

public fun claim_user_unsettled_fee_storage_rebate_admin<BaseToken, QuoteToken, FeeCoinType>(
    fees_manager: &mut FeesManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    _admin: &AdminCap,
    order_id: u128,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    claim_user_unsettled_fee_rebates_core<BaseToken, QuoteToken, FeeCoinType>(
        fees_manager,
        pool,
        balance_manager,
        order_id,
    );
}

public fun claim_protocol_unsettled_fee_storage_rebate<FeeCoinType>(
    fees_manager: &mut FeesManager,
    ctx: &mut TxContext,
) {
    fees_manager.validate_owner(ctx);

    claim_protocol_unsettled_fee_rebates_core<FeeCoinType>(fees_manager);
}

public fun claim_protocol_unsettled_fee_storage_rebate_admin<FeeCoinType>(
    fees_manager: &mut FeesManager,
    _admin: &AdminCap,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    claim_protocol_unsettled_fee_rebates_core<FeeCoinType>(fees_manager);
}

// === Public-Package Functions ===
/// Add unsettled fee for a specific order
///
/// This function stores fees that will be settled later based on order execution outcome.
/// It validates the order state and creates a new unsettled fee for the order.
///
/// Key validations:
/// - Order must be live or partially filled (not cancelled/filled/expired)
/// - Order must not be fully executed (must have remaining maker quantity)
/// - Fee amount must be greater than zero
/// - Order must not already have an unsettled fee (one-time addition only)
///
/// See `docs/unsettled-fees.md` for detailed explanation of the unsettled fees system.
public(package) fun add_to_user_unsettled_fees<CoinType>(
    fees_manager: &mut FeesManager,
    fee: Balance<CoinType>,
    order_info: &OrderInfo,
    ctx: &TxContext,
) {
    fees_manager.validate_owner(ctx);

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
    assert!(
        !fees_manager.user_unsettled_fees.contains(user_unsettled_fee_key),
        EUserUnsettledFeeAlreadyExists,
    );

    // Create the unsettled fee
    let user_unsettled_fee = UserUnsettledFee<CoinType> {
        balance: fee,
        order_quantity,
        maker_quantity,
    };
    fees_manager.user_unsettled_fees.add(user_unsettled_fee_key, user_unsettled_fee);

    event::emit(UserUnsettledFeeAdded<CoinType> {
        key: user_unsettled_fee_key,
        fee_value,
        order_quantity,
        maker_quantity,
    });
}

public(package) fun add_to_protocol_unsettled_fees<CoinType>(
    fees_manager: &mut FeesManager,
    fee: Balance<CoinType>,
    ctx: &TxContext,
) {
    fees_manager.validate_owner(ctx);

    if (fee.value() == 0) {
        fee.destroy_zero();
        return
    };

    let key = ProtocolUnsettledFeeKey<CoinType> {};
    if (fees_manager.protocol_unsettled_fees.contains(key)) {
        let balance: &mut Balance<CoinType> = fees_manager.protocol_unsettled_fees.borrow_mut(key);
        balance.join(fee);
    } else {
        fees_manager.protocol_unsettled_fees.add(key, fee);
    };
}

/// Settles fees for an order during cancellation, returning fees for the unfilled portion back
/// to the user and paying fees for the filled portion to the protocol.
///
/// By handling both the user refund and the protocol payment in a single transaction, it ensures
/// the `UnsettledFee` object is destroyed, which provides a gas storage rebate to the user.
///
/// Only the balance manager owner can claim fees for their orders.
///
/// Returns zero coin if no unsettled fees exist or balance is zero.
///
/// See `docs/unsettled-fees.md` for a detailed explanation of the unsettled fees system.
public(package) fun settle_user_fees<BaseToken, QuoteToken, FeeCoinType>(
    fees_manager: &mut FeesManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
    ctx: &mut TxContext,
): Coin<FeeCoinType> {
    fees_manager.validate_owner(ctx);

    let user_unsettled_fee_key = UserUnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!fees_manager.user_unsettled_fees.contains(user_unsettled_fee_key)) return coin::zero(ctx);

    let mut user_unsettled_fee: UserUnsettledFee<FeeCoinType> = fees_manager
        .user_unsettled_fees
        .remove(user_unsettled_fee_key);
    let user_unsettled_fee_value = user_unsettled_fee.balance.value();
    // TODO: Does this really should never happen?
    // Clean up unsettled fee if it has zero value. This should never happen, because adding
    // zero-value fees is restricted and fees are cleared on either user or protocol settlement.
    if (user_unsettled_fee_value == 0) {
        user_unsettled_fee.destroy_empty();
        return coin::zero(ctx)
    };

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
        fees_manager.add_to_protocol_unsettled_fees<FeeCoinType>(
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

fun claim_user_unsettled_fee_rebates_core<BaseToken, QuoteToken, FeeCoinType>(
    fees_manager: &mut FeesManager,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &BalanceManager,
    order_id: u128,
) {
    let user_unsettled_fee_key = UserUnsettledFeeKey {
        pool_id: object::id(pool),
        balance_manager_id: object::id(balance_manager),
        order_id,
    };

    if (!fees_manager.user_unsettled_fees.contains(user_unsettled_fee_key)) return;

    let user_unsettled_fee: UserUnsettledFee<FeeCoinType> = fees_manager
        .user_unsettled_fees
        .remove(user_unsettled_fee_key);

    user_unsettled_fee.destroy_empty();
}

fun claim_protocol_unsettled_fee_rebates_core<FeeCoinType>(fees_manager: &mut FeesManager) {
    let protocol_unsettled_fee_key = ProtocolUnsettledFeeKey<FeeCoinType> {};

    if (!fees_manager.protocol_unsettled_fees.contains(protocol_unsettled_fee_key)) return;

    let protocol_unsettled_fee: Balance<FeeCoinType> = fees_manager
        .protocol_unsettled_fees
        .remove(protocol_unsettled_fee_key);

    assert!(protocol_unsettled_fee.value() == 0, EProtocolUnsettledFeeNotEmpty);

    protocol_unsettled_fee.destroy_zero();
}

fun validate_owner(fees_manager: &FeesManager, ctx: &TxContext) {
    assert!(ctx.sender() == fees_manager.owner, EInvalidOwner);
}

// === Test Functions ===
/// Check if an unsettled fee exists for a specific order
#[test_only]
public fun has_user_unsettled_fee(
    fees_manager: &FeesManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): bool {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    fees_manager.user_unsettled_fees.contains(key)
}

/// Get the unsettled fee balance for a specific order
#[test_only]
public fun get_user_unsettled_fee_balance<CoinType>(
    fees_manager: &FeesManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): u64 {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let user_unsettled_fee: &UserUnsettledFee<CoinType> = fees_manager
        .user_unsettled_fees
        .borrow(key);
    user_unsettled_fee.balance.value()
}

/// Get the order parameters stored in an unsettled fee
#[test_only]
public fun get_user_unsettled_fee_order_params<CoinType>(
    fees_manager: &FeesManager,
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
): (u64, u64) {
    let key = UserUnsettledFeeKey { pool_id, balance_manager_id, order_id };
    let user_unsettled_fee: &UserUnsettledFee<CoinType> = fees_manager
        .user_unsettled_fees
        .borrow(key);
    (user_unsettled_fee.order_quantity, user_unsettled_fee.maker_quantity)
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
