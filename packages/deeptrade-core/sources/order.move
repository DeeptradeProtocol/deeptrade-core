module deeptrade_core::dt_order;

use deepbook::balance_manager::{BalanceManager, TradeProof};
use deepbook::constants;
use deepbook::order_info::OrderInfo;
use deepbook::pool::Pool;
use deeptrade_core::fee::{
    TradingFeeConfig,
    calculate_protocol_fees,
    calculate_input_coin_deepbook_fee,
    calculate_deep_reserves_coverage_order_fee
};
use deeptrade_core::fee_manager::FeeManager;
use deeptrade_core::helper::{
    calculate_deep_required,
    calculate_order_amount,
    get_sui_per_deep,
    calculate_market_order_params,
    calculate_order_taker_maker_ratio,
    apply_slippage,
    calculate_deep_fee_coverage_discount_rate,
    hundred_percent
};
use deeptrade_core::loyalty::LoyaltyProgram;
use deeptrade_core::treasury::{Treasury, join_coverage_fee, deep_reserves, split_deep_reserves};
use pyth::price_info::PriceInfoObject;
use std::type_name;
use std::u64;
use sui::balance;
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event;
use sui::sui::SUI;
use token::deep::DEEP;

// === Errors ===
/// Error when trying to use deep from reserves but there is not enough available
const EInsufficientDeepReserves: u64 = 1;
/// Error when user doesn't have enough coins to cover the required fee
const EInsufficientFee: u64 = 2;
/// Error when user doesn't have enough input coins to create the order
const EInsufficientInput: u64 = 3;
/// Error when the caller is not the owner of the balance manager
const EInvalidOwner: u64 = 4;
/// Error when actual deep required exceeds the max deep required
const EDeepRequiredExceedsMax: u64 = 5;
/// Error when actual coverage fee exceeds the max coverage fee
const ECoverageFeeExceedsMax: u64 = 6;

/// Not supported parameters errors
const ENotSupportedExpireTimestamp: u64 = 7;
const ENotSupportedSelfMatchingOption: u64 = 8;

const EInvalidSuiPerDeep: u64 = 9;
/// Error when the slippage is invalid (greater than 100% in billionths)
const EInvalidSlippage: u64 = 10;
const EInvalidInputCoinType: u64 = 11;

// === Structs ===
/// A plan for allocating DEEP tokens for an order's DeepBook fees.
///
/// It specifies how much DEEP to take from the user's wallet and how much to
/// supply from the treasury's reserves if the user's balance is insufficient.
public struct DeepPlan has copy, drop {
    /// Amount of DEEP to take from user's wallet
    from_user_wallet: u64,
    /// Amount of DEEP to take from user's balance manager
    from_balance_manager: u64,
    /// Amount of DEEP to take from treasury reserves
    from_deep_reserves: u64,
    /// Whether treasury DEEP reserves has enough DEEP to cover the order
    deep_reserves_cover_order: bool,
}

/// A plan for charging a coverage fee when the treasury's DEEP reserves are used.
///
/// This fee is charged in SUI as compensation for using the treasury's DEEP to
/// pay for an order's DeepBook fees. This struct specifies how much SUI to
/// take from the user's wallet and balance manager to pay this fee.
public struct CoverageFeePlan has copy, drop {
    from_wallet: u64,
    from_balance_manager: u64,
    /// Whether user has enough coins to cover the fee
    user_covers_fee: bool,
}

/// A plan for charging the Deeptrade treasury's protocol fees on an order.
///
/// The protocol fee is an additional fee charged by the Deeptrade treasury for its services,
/// paid in the order's input coin (base or quote). This plan calculates the
/// maker and taker portions of the fee and specifies an allocation of the payment between
/// the user's wallet and balance manager.
public struct ProtocolFeePlan has copy, drop {
    taker_fee_from_wallet: u64,
    taker_fee_from_balance_manager: u64,
    maker_fee_from_wallet: u64,
    maker_fee_from_balance_manager: u64,
    /// Whether user has enough coins to cover the fees
    user_covers_fee: bool,
}

/// A plan for depositing the required input coins into the balance manager.
///
/// To place an order on DeepBook, the necessary funds (base or quote tokens) must be
/// available in the user's balance manager. This plan calculates how many coins
/// to transfer from the user's wallet to the balance manager to cover the order.
public struct InputCoinDepositPlan has copy, drop {
    /// Amount of input coins to take from user's wallet
    from_user_wallet: u64,
    /// Whether user has enough input coins for the order
    user_has_enough_input_coin: bool,
}

// === Events ===
public struct TakerFeeCharged<phantom CoinType> has copy, drop {
    pool_id: ID,
    balance_manager_id: ID,
    order_id: u128,
    client_order_id: u64,
    taker_fee: u64,
}

// === Public-Mutative Functions ===
/// Creates a limit order on DeepBook using coins from various sources
/// This function orchestrates the entire limit order creation process through the following steps:
/// 1. Creates plans for:
///    - DEEP coin sourcing from user wallet and treasury reserves
///    - Coverage fee collection in SUI coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Sources DEEP coins according to the DEEP plan
///    - Collects coverage fees according to the coverage fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the limit order on DeepBook and returns the order info
/// 4. Plans and charges protocol fees based on order execution results
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance managing the order process
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - price: Order price in quote tokens per base token
/// - quantity: Order quantity in base tokens
/// - is_bid: True for buy orders, false for sell orders
/// - expire_timestamp: Order expiration timestamp
/// - order_type: Type of order (e.g., GTC, IOC, FOK)
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
public fun create_limit_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    treasury: &mut Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    mut deep_coin: Coin<DEEP>,
    mut sui_coin: Coin<SUI>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>, Coin<DEEP>, Coin<SUI>) {
    treasury.verify_version();

    // Read more about expire timestamp and self matching option limitations in docs/unsettled-fees.md
    // Verify the order expire timestamp is the max possible expire timestamp
    let max_expire_timestamp = constants::max_u64();
    assert!(expire_timestamp == max_expire_timestamp, ENotSupportedExpireTimestamp);

    // Verify the self matching option is self matching allowed
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    let deep_required = calculate_deep_required(pool, quantity, price);
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    let (proof, protocol_fee_discount_rate) = prepare_order_execution(
        treasury,
        trading_fee_config,
        loyalty_program,
        pool,
        reference_pool,
        deep_usd_price_info,
        sui_usd_price_info,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &mut deep_coin,
        &mut sui_coin,
        deep_required,
        order_amount,
        is_bid,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
        clock,
        ctx,
    );

    let order_info = pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        true, // Using DEEP for fees
        expire_timestamp,
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true, // DEEP fee type
        ctx,
    );

    (order_info, base_coin, quote_coin, deep_coin, sui_coin)
}

/// Creates a market order on DeepBook using coins from various sources
/// This function orchestrates the entire market order creation process through the following steps:
/// 1. Creates plans for:
///    - DEEP coin sourcing from user wallet and treasury reserves
///    - Coverage fee collection in SUI coins
///    - Input coin deposits from wallet to balance manager
/// 2. Executes the plans through shared preparation logic that:
///    - Sources DEEP coins according to the DEEP plan
///    - Collects coverage fees according to the coverage fee plan
///    - Deposits input coins according to the input coin deposit plan
/// 3. Places the market order on DeepBook and returns the order info
/// 4. Plans and charges protocol fees based on order execution results
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance managing the order process
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool for price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks). For bids, this amount
///                 will be converted into base quantity using current order book state
/// - is_bid: True for buy orders, false for sell orders
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
public fun create_market_order<BaseToken, QuoteToken, ReferenceBaseAsset, ReferenceQuoteAsset>(
    treasury: &mut Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    mut deep_coin: Coin<DEEP>,
    mut sui_coin: Coin<SUI>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>, Coin<DEEP>, Coin<SUI>) {
    treasury.verify_version();

    // Verify the self matching option is self matching allowed. Read more about self matching option
    // limitations in docs/unsettled-fees.md
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    let (base_quantity, deep_required) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    let (proof, protocol_fee_discount_rate) = prepare_order_execution(
        treasury,
        trading_fee_config,
        loyalty_program,
        pool,
        reference_pool,
        deep_usd_price_info,
        sui_usd_price_info,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &mut deep_coin,
        &mut sui_coin,
        deep_required,
        order_amount,
        is_bid,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
        clock,
        ctx,
    );

    let order_info = pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        true, // Using DEEP for fees
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true, // DEEP fee type
        ctx,
    );

    (order_info, base_coin, quote_coin, deep_coin, sui_coin)
}

/// Creates a limit order on DeepBook using coins from user's wallet for whitelisted pools
/// This function orchestrates the order creation process:
/// 1. Calculates required order amount based on price and quantity
/// 2. Prepares order execution by handling coin deposits (see `prepare_whitelisted_order_execution`)
/// 3. Places the limit order on DeepBook
/// 4. Plans and charges protocol fees based on order execution results
/// 5. Returns the order info
///
/// Note: This function is optimized for whitelisted pools and doesn't require treasury reserves
/// to be used.
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - price: Order price in quote tokens per base token
/// - quantity: Order quantity in base tokens
/// - is_bid: True for buy orders, false for sell orders
/// - expire_timestamp: Order expiration timestamp
/// - order_type: Type of order (e.g., GTC, IOC, FOK)
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for timestamp verification
public fun create_limit_order_whitelisted<BaseToken, QuoteToken>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    // Read more about expire timestamp and self matching option limitations in docs/unsettled-fees.md
    // Verify the order expire timestamp is the max possible expire timestamp
    let max_expire_timestamp = constants::max_u64();
    assert!(expire_timestamp == max_expire_timestamp, ENotSupportedExpireTimestamp);

    // Verify the self matching option is self matching allowed
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    let order_amount = calculate_order_amount(quantity, price, is_bid);

    let (proof, protocol_fee_discount_rate) = prepare_whitelisted_order_execution(
        trading_fee_config,
        loyalty_program,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    let order_info = pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        true, // Using DEEP for fees (though whitelisted pools don't require fees)
        expire_timestamp,
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true, // DEEP fee type
        ctx,
    );

    (order_info, base_coin, quote_coin)
}

/// Creates a market order on DeepBook using coins from user's wallet for whitelisted pools
/// This function orchestrates the order creation process:
/// 1. Calculates base quantity from order amount using current order book state
/// 2. Prepares order execution by handling coin deposits (see `prepare_whitelisted_order_execution`)
/// 3. Places the market order on DeepBook
/// 4. Plans and charges protocol fees based on order execution results
/// 5. Returns the order info
///
/// Note: This function is optimized for whitelisted pools and doesn't require treasury reserves
/// to be used.
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for order book state
public fun create_market_order_whitelisted<BaseToken, QuoteToken>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    // Verify the self matching option is self matching allowed. Read more about self matching option
    // limitations in docs/unsettled-fees.md
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    let (base_quantity, _) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );

    let (proof, protocol_fee_discount_rate) = prepare_whitelisted_order_execution(
        trading_fee_config,
        loyalty_program,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    let order_info = pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        true, // Using DEEP for fees (though whitelisted pools don't require fees)
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        protocol_fee_discount_rate,
        true, // DEEP fee type
        ctx,
    );

    (order_info, base_coin, quote_coin)
}

/// Creates a limit order on DeepBook using input coins for fees
/// This function orchestrates the limit order creation process through the following steps:
/// 1. Creates plan for input coin deposits from wallet to balance manager
/// 2. Executes the plan through shared preparation logic
/// 3. Places the limit order on DeepBook
/// 4. Plans and charges protocol fees based on order execution results
/// 5. Returns the order info
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - price: Order price in quote tokens per base token
/// - quantity: Order quantity in base tokens
/// - is_bid: True for buy orders, false for sell orders
/// - expire_timestamp: Order expiration timestamp
/// - order_type: Type of order (e.g., GTC, IOC, FOK)
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for timestamp verification
public fun create_limit_order_input_fee<BaseToken, QuoteToken>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    price: u64,
    quantity: u64,
    is_bid: bool,
    expire_timestamp: u64,
    order_type: u8,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    // Read more about expire timestamp and self matching option limitations in docs/unsettled-fees.md
    // Verify the order expire timestamp is the max possible expire timestamp
    let max_expire_timestamp = constants::max_u64();
    assert!(expire_timestamp == max_expire_timestamp, ENotSupportedExpireTimestamp);

    // Verify the self matching option is self matching allowed
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    let order_amount = calculate_order_amount(quantity, price, is_bid);
    let loyalty_fee_discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());

    let proof = prepare_input_fee_order_execution(
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    let order_info = pool.place_limit_order(
        balance_manager,
        &proof,
        client_order_id,
        order_type,
        self_matching_option,
        price,
        quantity,
        is_bid,
        false, // Using input coins for fees
        expire_timestamp,
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        loyalty_fee_discount_rate, // Intentional: only loyalty discount can be applied to input fee orders
        false, // Input coin fee type
        ctx,
    );

    (order_info, base_coin, quote_coin)
}

/// Creates a market order on DeepBook using input coins for fees
/// This function orchestrates the market order creation process through the following steps:
/// 1. Creates plan for input coin deposits from wallet to balance manager
/// 2. Executes the plan through shared preparation logic
/// 3. Places the market order on DeepBook
/// 4. Plans and charges protocol fees based on order execution results
/// 5. Returns the order info
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - self_matching_option: Self-matching behavior configuration
/// - client_order_id: Client-provided order identifier
/// - clock: System clock for timestamp verification
public fun create_market_order_input_fee<BaseToken, QuoteToken>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    mut base_coin: Coin<BaseToken>,
    mut quote_coin: Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    self_matching_option: u8,
    client_order_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (OrderInfo, Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    // Verify the self matching option is self matching allowed. Read more about self matching option
    // limitations in docs/unsettled-fees.md
    assert!(
        self_matching_option == constants::self_matching_allowed(),
        ENotSupportedSelfMatchingOption,
    );

    // We use calculate_market_order_params to get base quantity, which uses `get_quantity_out` under the hood,
    // since `get_quantity_out` returns `base_quantity` without applying DeepBook fees to it.
    // We do need that, since we have to apply our protocol fee & deepbook fee on top of the order amount.
    let (base_quantity, _) = calculate_market_order_params<BaseToken, QuoteToken>(
        pool,
        order_amount,
        is_bid,
        clock,
    );
    let loyalty_fee_discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());

    let proof = prepare_input_fee_order_execution(
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        order_amount,
        is_bid,
        ctx,
    );

    let order_info = pool.place_market_order(
        balance_manager,
        &proof,
        client_order_id,
        self_matching_option,
        base_quantity,
        is_bid,
        false, // Using input coins for fees
        clock,
        ctx,
    );

    charge_protocol_fees(
        fee_manager,
        trading_fee_config,
        pool,
        balance_manager,
        &mut base_coin,
        &mut quote_coin,
        &order_info,
        order_amount,
        loyalty_fee_discount_rate, // Intentional: only loyalty discount can be applied to input fee orders
        false, // Input coin fee type
        ctx,
    );

    (order_info, base_coin, quote_coin)
}

/// Cancels an order and settles any associated with the order unsettled fees
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version
/// - fee_manager: User's fee manager for settling fees
/// - pool: The trading pool where the order was placed
/// - balance_manager: User's balance manager
/// - order_id: ID of the order to cancel
/// - clock: System clock for timestamp verification
///
/// Returns the settled fees as a coin of the specified type
public fun cancel_order_and_settle_fees<BaseAsset, QuoteAsset, UnsettledFeeCoinType>(
    treasury: &Treasury,
    fee_manager: &mut FeeManager,
    pool: &mut Pool<BaseAsset, QuoteAsset>,
    balance_manager: &mut BalanceManager,
    order_id: u128,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<UnsettledFeeCoinType> {
    treasury.verify_version();

    let settled_fees = fee_manager.settle_user_fees<BaseAsset, QuoteAsset, UnsettledFeeCoinType>(
        pool,
        balance_manager,
        order_id,
        ctx,
    );

    // Proof generation requires the transaction sender to be the balance manager owner
    let trade_proof = balance_manager.generate_proof_as_owner(ctx);
    pool.cancel_order(balance_manager, &trade_proof, order_id, clock, ctx);

    settled_fees
}

// === Public-Package Functions ===
/// Core logic function that orchestrates the creation of both limit and market orders using coins from various sources
/// Coordinates all requirements by analyzing available resources and calculating necessary allocations
/// Creates comprehensive plans for DEEP coins sourcing, coverage fee charging, and input coin deposits
///
/// Parameters:
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - deep_required: Amount of DEEP required for the order
/// - balance_manager_deep: Amount of DEEP in user's balance manager
/// - balance_manager_sui: Amount of SUI in user's balance manager
/// - balance_manager_input_coin: Amount of input coins (base/quote) in user's balance manager
/// - deep_in_wallet: Amount of DEEP in user's wallet
/// - sui_in_wallet: Amount of SUI in user's wallet
/// - wallet_input_coin: Amount of input coins (base/quote) in user's wallet
/// - treasury_deep_reserves: Amount of DEEP available in treasury reserves
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - input_coin_is_sui: Whether the input coin is SUI
/// - input_coin_is_deep: Whether the input coin is DEEP
///
/// Returns a tuple with three structured plans:
/// - DeepPlan: Coordinates DEEP coin sourcing from user wallet and treasury reserves
/// - CoverageFeePlan: Specifies coverage fee amount and sources for SUI fee payment
/// - InputCoinDepositPlan: Determines how input coins will be sourced for the order
public(package) fun create_order_core(
    is_pool_whitelisted: bool,
    deep_required: u64,
    balance_manager_deep: u64,
    balance_manager_sui: u64,
    mut balance_manager_input_coin: u64,
    deep_in_wallet: u64,
    sui_in_wallet: u64,
    wallet_input_coin: u64,
    treasury_deep_reserves: u64,
    order_amount: u64,
    sui_per_deep: u64,
    input_coin_is_sui: bool,
    input_coin_is_deep: bool,
): (DeepPlan, CoverageFeePlan, InputCoinDepositPlan) {
    // Sanity check: input coin cannot be flagged as both SUI and DEEP. Either one of them, or none
    assert!(!(input_coin_is_sui && input_coin_is_deep), EInvalidInputCoinType);

    // Step 1: Determine DEEP requirements
    let deep_plan = get_deep_plan(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        deep_in_wallet,
        treasury_deep_reserves,
    );

    // If input coin is DEEP, `balance_manager_input_coin` and `balance_manager_deep` are the same balance amounts.
    // So, if the `balance_manager_deep` is planned to be consumed by the DeepPlan, we need to decrease
    // the `balance_manager_input_coin` correspondingly for further calculations of the InputCoinDepositPlan
    if (input_coin_is_deep && deep_plan.from_balance_manager > 0) {
        balance_manager_input_coin = balance_manager_input_coin - deep_plan.from_balance_manager;
    };

    // Step 2: Determine coverage fee charging plan
    let coverage_fee_plan = get_coverage_fee_plan(
        deep_plan.from_deep_reserves,
        is_pool_whitelisted,
        sui_per_deep,
        sui_in_wallet,
        balance_manager_sui,
    );

    // If input coin is SUI, `balance_manager_input_coin` and `balance_manager_sui` are the same balance amounts.
    // So, if the `balance_manager_sui` is planned to be consumed by the CoverageFeePlan, we need to decrease
    // the `balance_manager_input_coin` correspondingly for further calculations of the InputCoinDepositPlan
    if (input_coin_is_sui && coverage_fee_plan.from_balance_manager > 0) {
        balance_manager_input_coin =
            balance_manager_input_coin - coverage_fee_plan.from_balance_manager;
    };

    // Step 3: Determine input coin deposit plan
    let deposit_plan = get_input_coin_deposit_plan(
        order_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    (deep_plan, coverage_fee_plan, deposit_plan)
}

/// Analyzes DEEP coin requirements for an order and creates a sourcing plan
/// Evaluates user's available DEEP coins and determines if treasury reserves are needed
/// Calculates optimal allocation from user wallet, balance manager, and treasury reserves
///
/// Returns a DeepPlan structure with the following information:
/// - from_user_wallet: Amount of DEEP to take from user's wallet
/// - from_balance_manager: Amount of DEEP to take from user's balance manager
/// - from_deep_reserves: Amount of DEEP to take from treasury reserves
/// - deep_reserves_cover_order: Whether treasury has enough DEEP to cover what's needed
public(package) fun get_deep_plan(
    is_pool_whitelisted: bool,
    deep_required: u64,
    balance_manager_deep: u64,
    deep_in_wallet: u64,
    treasury_deep_reserves: u64,
): DeepPlan {
    // If pool is whitelisted, no DEEP is needed
    if (is_pool_whitelisted) {
        return DeepPlan {
            from_user_wallet: 0,
            from_balance_manager: 0,
            from_deep_reserves: 0,
            deep_reserves_cover_order: true,
        }
    };

    // Calculate how much DEEP the user has available
    let user_deep_total = balance_manager_deep + deep_in_wallet;

    if (user_deep_total >= deep_required) {
        // User has enough DEEP
        // Determine how much to take from wallet and balance manager based on what's available
        let (from_wallet, from_balance_manager) = if (balance_manager_deep >= deep_required) {
            // Nothing needed from wallet if balance manager has enough
            (0, deep_required)
        } else {
            // All from balance manager, remainder from wallet
            (deep_required - balance_manager_deep, balance_manager_deep)
        };

        DeepPlan {
            from_user_wallet: from_wallet,
            from_balance_manager,
            from_deep_reserves: 0,
            deep_reserves_cover_order: true,
        }
    } else {
        // Need treasury DEEP since user doesn't have enough
        let from_wallet = deep_in_wallet; // Take all from wallet
        let from_balance_manager = balance_manager_deep; // Take all from balance manager
        let still_needed = deep_required - user_deep_total;
        let has_enough = treasury_deep_reserves >= still_needed;

        if (!has_enough) {
            return DeepPlan {
                from_user_wallet: 0,
                from_balance_manager: 0,
                from_deep_reserves: 0,
                deep_reserves_cover_order: false,
            }
        };

        DeepPlan {
            from_user_wallet: from_wallet,
            from_balance_manager,
            from_deep_reserves: still_needed,
            deep_reserves_cover_order: true,
        }
    }
}

/// Creates a coverage fee plan for order execution by determining optimal sources for coverage fee payment
/// in SUI coins.
/// Returns early with zero fees for whitelisted pools or when not using treasury DEEP.
///
/// Parameters:
/// - deep_from_reserves: Amount of DEEP to be taken from treasury reserves
/// - is_pool_whitelisted: Whether the pool is whitelisted by DeepBook
/// - sui_per_deep: Current DEEP/SUI price from reference pool
/// - sui_in_wallet: Amount of SUI available in user's wallet
/// - balance_manager_sui: Amount of SUI available in user's balance manager
///
/// Returns:
/// - CoverageFeePlan: Struct containing:
///   - from_wallet: Coverage fee amount from user's wallet
///   - from_balance_manager: Coverage fee amount from user's balance manager
///   - user_covers_fee: Whether user has sufficient funds to cover fees
///
/// Flow:
/// 1. Returns zero fee plan if pool is whitelisted, or not using treasury DEEP
/// 2. Calculates coverage fee
/// 3. Returns insufficient fee plan if user lacks total funds
/// 4. Plans coverage fee collection from available sources
public(package) fun get_coverage_fee_plan(
    deep_from_reserves: u64,
    is_pool_whitelisted: bool,
    sui_per_deep: u64,
    sui_in_wallet: u64,
    balance_manager_sui: u64,
): CoverageFeePlan {
    // No fee for whitelisted pools, or when not using treasury DEEP
    if (is_pool_whitelisted || deep_from_reserves == 0) {
        return zero_coverage_fee_plan()
    };

    // Sanity check: SUI per DEEP must be greater than zero. Otherwise, the price retrieving process is flawed
    assert!(sui_per_deep > 0, EInvalidSuiPerDeep);

    // Calculate coverage fee amount
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );

    // Check if user has enough total coins
    let total_available = sui_in_wallet + balance_manager_sui;
    if (total_available < coverage_fee) {
        return insufficient_coverage_fee_plan()
    };

    // Plan coverage fee collection
    let (from_wallet, from_balance_manager) = plan_fee_collection(
        coverage_fee,
        sui_in_wallet,
        balance_manager_sui,
    );

    CoverageFeePlan {
        from_wallet,
        from_balance_manager,
        user_covers_fee: true,
    }
}

/// Creates a protocol fee plan for order execution
/// Calculates taker and maker fees based on order execution status and determines the allocation
/// of those fees between the user's wallet and balance manager.
///
/// Parameters:
/// - order_info: Information about the executed order
/// - taker_fee_rate: Protocol taker fee rate in billionths
/// - maker_fee_rate: Protocol maker fee rate in billionths
/// - coin_in_wallet: Amount of input coins available in user's wallet
/// - coin_in_balance_manager: Amount of input coins available in user's balance manager
/// - order_amount: Total order amount
/// - discount_rate: Discount rate applied to fees
///
/// Returns a ProtocolFeePlan with fee amounts from different sources
public(package) fun get_protocol_fee_plan(
    order_info: &OrderInfo,
    taker_fee_rate: u64,
    maker_fee_rate: u64,
    coin_in_wallet: u64,
    coin_in_balance_manager: u64,
    order_amount: u64,
    discount_rate: u64,
): ProtocolFeePlan {
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        taker_fee_rate,
        maker_fee_rate,
        order_amount,
        discount_rate,
    );

    // If no fee, return early
    // This can occur for IOC orders that don't find matching orders, resulting in zero execution
    // and thus zero taker fee (no execution) and zero maker fee (no remaining in order book)
    if (total_fee == 0) {
        return zero_protocol_fee_plan()
    };

    // Check if user has enough total coins
    let total_available = coin_in_wallet + coin_in_balance_manager;
    if (total_available < total_fee) {
        return insufficient_protocol_fee_plan()
    };

    // Plan taker fee collection
    let (taker_fee_from_wallet, taker_fee_from_balance_manager) = plan_fee_collection(
        taker_fee,
        coin_in_wallet,
        coin_in_balance_manager,
    );

    // Adjust available amounts for maker fee planning
    let remaining_in_wallet = coin_in_wallet - taker_fee_from_wallet;
    let remaining_in_bm = coin_in_balance_manager - taker_fee_from_balance_manager;

    // Plan maker fee collection
    let (maker_fee_from_wallet, maker_fee_from_balance_manager) = plan_fee_collection(
        maker_fee,
        remaining_in_wallet,
        remaining_in_bm,
    );

    ProtocolFeePlan {
        taker_fee_from_wallet,
        taker_fee_from_balance_manager,
        maker_fee_from_wallet,
        maker_fee_from_balance_manager,
        user_covers_fee: true,
    }
}

/// Creates an input coin deposit plan for order execution
/// Specifies the allocation of required input coins between the user's wallet and balance manager.
/// For bid orders, calculates quote coins needed; for ask orders, calculates base coins needed
///
/// Returns an InputCoinDepositPlan structure with the following information:
/// - from_user_wallet: Amount of input coins to take from user's wallet
/// - user_has_enough_input_coin: Whether user has enough input coins for the order
public(package) fun get_input_coin_deposit_plan(
    required_amount: u64,
    wallet_balance: u64,
    balance_manager_balance: u64,
): InputCoinDepositPlan {
    // Check if we already have enough in the balance manager
    if (balance_manager_balance >= required_amount) {
        return InputCoinDepositPlan {
            from_user_wallet: 0,
            user_has_enough_input_coin: true,
        }
    };

    // Calculate how much more is needed
    let additional_needed = required_amount - balance_manager_balance;
    let has_enough = wallet_balance >= additional_needed;

    if (!has_enough) {
        return InputCoinDepositPlan {
            from_user_wallet: 0,
            user_has_enough_input_coin: false,
        }
    };

    InputCoinDepositPlan {
        from_user_wallet: additional_needed,
        user_has_enough_input_coin: true,
    }
}

/// Plans optimal fee collection strategy from available sources, prioritizing balance manager usage.
/// Returns early with zero amounts if no fee to collect.
///
/// Parameters:
/// - fee_amount: Amount of fee to be collected
/// - available_in_wallet: Amount of coins available in user's wallet
/// - available_in_bm: Amount of coins available in user's balance manager
///
/// Returns:
/// - (u64, u64): Tuple containing:
///   - amount_to_collect_from_wallet: Amount to collect from wallet
///   - amount_to_collect_from_balance_manager: Amount to collect from balance manager
///
/// Flow:
/// 1. Returns (0, 0) if fee amount is zero
/// 2. Verifies total available funds are sufficient
/// 3. Takes entire amount from balance manager if possible
/// 4. Otherwise, takes maximum from balance manager and remainder from wallet
///
/// Aborts:
/// - EInsufficientFee: If total available funds are less than required fee
public(package) fun plan_fee_collection(
    fee_amount: u64,
    available_in_wallet: u64,
    available_in_bm: u64,
): (u64, u64) {
    // If no fee to collect, return zeros
    if (fee_amount == 0) return (0, 0);

    // Verify user has enough total funds before proceeding
    assert!(available_in_wallet + available_in_bm >= fee_amount, EInsufficientFee);

    // Safely plan fee collection knowing user has enough funds
    if (available_in_bm >= fee_amount) {
        // Take all from balance manager if possible
        (0, fee_amount)
    } else {
        // Take what we can from balance manager and rest from wallet
        let from_bm = available_in_bm;
        let from_wallet = fee_amount - from_bm;
        (from_wallet, from_bm)
    }
}

/// Validates that actual DeepBook and coverage fees don't exceed maximum allowed amounts with slippage
///
/// Parameters:
/// - deep_required: Actual amount of DEEP required for the order
/// - deep_from_reserves: Amount of DEEP to be taken from treasury reserves
/// - sui_per_deep: Current DEEP/SUI price from either oracle or reference pool
/// - estimated_deep_required: Estimated DEEP requirement used to calculate maximum allowed one
/// - estimated_deep_required_slippage: Slippage in billionths applied to estimated DEEP requirement for maximum calculation
/// - estimated_sui_fee: Estimated coverage fee used to calculate maximum allowed coverage fee
/// - estimated_sui_fee_slippage: Slippage in billionths applied to estimated coverage fee for maximum calculation
public(package) fun validate_fees_against_max(
    deep_required: u64,
    deep_from_reserves: u64,
    sui_per_deep: u64,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
) {
    // Validate slippage values
    assert!(estimated_deep_required_slippage <= hundred_percent(), EInvalidSlippage);
    assert!(estimated_sui_fee_slippage <= hundred_percent(), EInvalidSlippage);

    // Calculate maximum allowed fees
    let max_deep_required = apply_slippage(
        estimated_deep_required,
        estimated_deep_required_slippage,
    );
    let max_coverage_fee = apply_slippage(estimated_sui_fee, estimated_sui_fee_slippage);

    // Validate DEEP fee
    assert!(deep_required <= max_deep_required, EDeepRequiredExceedsMax);

    // Validate coverage fee (only applies when using treasury DEEP reserves)
    if (deep_from_reserves > 0) {
        let actual_coverage_fee = calculate_deep_reserves_coverage_order_fee(
            sui_per_deep,
            deep_from_reserves,
        );
        assert!(actual_coverage_fee <= max_coverage_fee, ECoverageFeeExceedsMax);
    };
}

/// Charges protocol fees for a given order using input coins
/// Calculates taker and maker fees based on order execution status and collects fees
/// from user's wallet and balance manager according to the protocol fee plan
///
/// Parameters:
/// - fee_manager: User's fee manager for collecting protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - pool: The trading pool where the order was placed
/// - balance_manager: User's balance manager
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_info: Information about the executed order
/// - order_amount: Total order amount
/// - discount_rate: Discount rate applied to fees
/// - deep_fee_type: Whether using DEEP fee type rates (true) or input coin fee type rates (false)
public(package) fun charge_protocol_fees<BaseToken, QuoteToken>(
    fee_manager: &mut FeeManager,
    trading_fee_config: &TradingFeeConfig,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    order_info: &OrderInfo,
    order_amount: u64,
    discount_rate: u64,
    deep_fee_type: bool,
    ctx: &mut TxContext,
) {
    // Get the protocol fee rates for the pool
    let pool_protocol_fee_config = trading_fee_config.get_pool_fee_config(pool);
    let (protocol_taker_fee_rate, protocol_maker_fee_rate) = if (deep_fee_type) {
        pool_protocol_fee_config.deep_fee_type_rates()
    } else {
        pool_protocol_fee_config.input_coin_fee_type_rates()
    };

    let is_bid = order_info.is_bid();

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Get fee plan
    let fee_plan = get_protocol_fee_plan(
        order_info,
        protocol_taker_fee_rate,
        protocol_maker_fee_rate,
        wallet_input_coin,
        balance_manager_input_coin,
        order_amount,
        discount_rate,
    );

    // Execute protocol fee plan
    if (is_bid) {
        execute_protocol_fee_plan(
            fee_manager,
            balance_manager,
            quote_coin,
            order_info,
            &fee_plan,
            ctx,
        );
    } else {
        execute_protocol_fee_plan(
            fee_manager,
            balance_manager,
            base_coin,
            order_info,
            &fee_plan,
            ctx,
        );
    };
}

/// Prepares order execution by handling all common order creation logic:
/// 1. Verifies the caller owns the balance manager
/// 2. Creates plans for DEEP sourcing, coverage fee collection, and input coin deposit
/// 3. Verifies that actual DEEP required and coverage fee don't exceed maximums with slippage
/// 4. Executes the plans in sequence:
///    - Sources DEEP coins from user wallet and treasury reserves according to DeepPlan
///    - Collects coverage fees in SUI coins according to CoverageFeePlan
///    - Deposits required input coins according to InputCoinDepositPlan
/// 5. Returns unused DEEP and SUI coins to the caller
/// 6. Returns the balance manager proof needed for order placement and protocol fee discount rate
///
/// This function contains the shared execution logic between limit and market orders,
/// processing the plans created by create_order_core.
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance managing the order process
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - reference_pool: Reference pool used for fallback DEEP/SUI price calculation
/// - deep_usd_price_info: Pyth price info object for DEEP/USD price
/// - sui_usd_price_info: Pyth price info object for SUI/USD price
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - deep_coin: DEEP coins from user's wallet
/// - sui_coin: SUI coins for fee payment
/// - deep_required: Amount of DEEP required for the order
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - estimated_deep_required: Amount of DEEP tokens required for the order creation
/// - estimated_deep_required_slippage: Maximum acceptable slippage for estimated DEEP requirement in billionths (e.g., 10_000_000 = 1%)
/// - estimated_sui_fee: Estimated SUI fee which we can take as a protocol for the order creation
/// - estimated_sui_fee_slippage: Maximum acceptable slippage for estimated SUI fee in billionths (e.g., 10_000_000 = 1%)
/// - clock: System clock for timestamp verification
public(package) fun prepare_order_execution<
    BaseToken,
    QuoteToken,
    ReferenceBaseAsset,
    ReferenceQuoteAsset,
>(
    treasury: &mut Treasury,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &Pool<BaseToken, QuoteToken>,
    reference_pool: &Pool<ReferenceBaseAsset, ReferenceQuoteAsset>,
    deep_usd_price_info: &PriceInfoObject,
    sui_usd_price_info: &PriceInfoObject,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    deep_coin: &mut Coin<DEEP>,
    sui_coin: &mut Coin<SUI>,
    deep_required: u64,
    order_amount: u64,
    is_bid: bool,
    estimated_deep_required: u64,
    estimated_deep_required_slippage: u64,
    estimated_sui_fee: u64,
    estimated_sui_fee_slippage: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (TradeProof, u64) {
    treasury.verify_version();

    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Get the best DEEP/SUI price
    let sui_per_deep = get_sui_per_deep(
        deep_usd_price_info,
        sui_usd_price_info,
        reference_pool,
        clock,
    );

    let is_pool_whitelisted = pool.whitelisted();

    // Get balances from balance manager
    let balance_manager_deep = balance_manager.balance<DEEP>();
    let balance_manager_sui = balance_manager.balance<SUI>();
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let deep_in_wallet = deep_coin.value();
    let sui_in_wallet = sui_coin.value();
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    let treasury_deep_reserves = deep_reserves(treasury);
    let max_deep_fee_coverage_discount_rate = trading_fee_config
        .get_pool_fee_config(pool)
        .max_deep_fee_coverage_discount_rate();

    // Determine input coin type
    let input_coin_is_sui = if (is_bid)
        type_name::with_original_ids<QuoteToken>() == type_name::with_original_ids<SUI>()
    else type_name::with_original_ids<BaseToken>() == type_name::with_original_ids<SUI>();
    let input_coin_is_deep = if (is_bid)
        type_name::with_original_ids<QuoteToken>() == type_name::with_original_ids<DEEP>()
    else type_name::with_original_ids<BaseToken>() == type_name::with_original_ids<DEEP>();

    let (deep_plan, coverage_fee_plan, input_coin_deposit_plan) = create_order_core(
        is_pool_whitelisted,
        deep_required,
        balance_manager_deep,
        balance_manager_sui,
        balance_manager_input_coin,
        deep_in_wallet,
        sui_in_wallet,
        wallet_input_coin,
        treasury_deep_reserves,
        order_amount,
        sui_per_deep,
        input_coin_is_sui,
        input_coin_is_deep,
    );

    validate_fees_against_max(
        deep_required,
        deep_plan.from_deep_reserves,
        sui_per_deep,
        estimated_deep_required,
        estimated_deep_required_slippage,
        estimated_sui_fee,
        estimated_sui_fee_slippage,
    );

    // Calculate total protocol fees discount rate
    let coverage_discount_rate = calculate_deep_fee_coverage_discount_rate(
        max_deep_fee_coverage_discount_rate,
        deep_plan.from_deep_reserves,
        deep_required,
    );
    let loyalty_discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());

    // Ensure the total discount rate doesn't exceed 100%
    let total_discount_rate = u64::min(
        coverage_discount_rate + loyalty_discount_rate,
        hundred_percent(),
    );

    execute_deep_plan(treasury, balance_manager, deep_coin, &deep_plan, ctx);

    execute_coverage_fee_plan(
        treasury,
        balance_manager,
        sui_coin,
        &coverage_fee_plan,
        ctx,
    );

    execute_input_coin_deposit_plan(
        balance_manager,
        base_coin,
        quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Generate and return proof and protocol fee discount rate
    (balance_manager.generate_proof_as_owner(ctx), total_discount_rate)
}

/// Prepares order execution for whitelisted pools by handling coin deposits
/// This function contains the shared logic for both limit and market orders in whitelisted pools,
/// focusing only on input coin management without DEEP or fee handling
///
/// Steps:
/// 1. Verifies the caller owns the balance manager
/// 2. Creates and executes input coin deposit plan
/// 3. Returns the balance manager proof needed for order placement and protocol fee discount rate
///
/// Parameters:
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: Loyalty program instance
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
public(package) fun prepare_whitelisted_order_execution<BaseToken, QuoteToken>(
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    ctx: &mut TxContext,
): (TradeProof, u64) {
    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Calculate the total discount rate for the protocol fees
    let max_deep_fee_coverage_discount_rate = trading_fee_config
        .get_pool_fee_config(pool)
        .max_deep_fee_coverage_discount_rate();
    let loyalty_discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());

    // Ensure the total discount rate doesn't exceed 100%
    // Intentional: whitelisted pools get maximum DEEP fee coverage discount by design
    let total_discount_rate = u64::min(
        max_deep_fee_coverage_discount_rate + loyalty_discount_rate,
        hundred_percent(),
    );

    let input_coin_deposit_plan = get_input_coin_deposit_plan(
        order_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    execute_input_coin_deposit_plan(
        balance_manager,
        base_coin,
        quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    // Generate and return proof and protocol fee discount rate
    (balance_manager.generate_proof_as_owner(ctx), total_discount_rate)
}

/// Prepares order execution by handling input coin fee and deposit logic
/// 1. Verifies the caller owns the balance manager
/// 2. Creates plan for input coin deposits from wallet to balance manager
/// 3. Executes the plan
/// 4. Returns the balance manager proof needed for order placement
///
/// Parameters:
/// - pool: The trading pool where the order will be placed
/// - balance_manager: User's balance manager for managing coin deposits
/// - base_coin: Base token coins from user's wallet
/// - quote_coin: Quote token coins from user's wallet
/// - order_amount: Order amount in quote tokens (for bids) or base tokens (for asks)
/// - is_bid: True for buy orders, false for sell orders
/// - ctx: Transaction context
public(package) fun prepare_input_fee_order_execution<BaseToken, QuoteToken>(
    pool: &Pool<BaseToken, QuoteToken>,
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    order_amount: u64,
    is_bid: bool,
    ctx: &mut TxContext,
): TradeProof {
    // Verify the caller owns the balance manager
    assert!(balance_manager.owner() == ctx.sender(), EInvalidOwner);

    // Get balances from balance manager
    let balance_manager_base = balance_manager.balance<BaseToken>();
    let balance_manager_quote = balance_manager.balance<QuoteToken>();
    let balance_manager_input_coin = if (is_bid) balance_manager_quote else balance_manager_base;

    // Get balances from wallet coins
    let base_in_wallet = base_coin.value();
    let quote_in_wallet = quote_coin.value();
    let wallet_input_coin = if (is_bid) quote_in_wallet else base_in_wallet;

    // Calculate DeepBook fee. It's safe and intentional to overestimate by using the taker fee rate,
    // since DeepBook will return any unused portion
    let (deepbook_taker_fee, _, _) = pool.pool_trade_params();
    let deepbook_fee = calculate_input_coin_deepbook_fee(order_amount, deepbook_taker_fee);

    // Calculate total amount needed to be on the balance manager
    let total_amount = order_amount + deepbook_fee;

    let input_coin_deposit_plan = get_input_coin_deposit_plan(
        total_amount,
        wallet_input_coin,
        balance_manager_input_coin,
    );

    execute_input_coin_deposit_plan(
        balance_manager,
        base_coin,
        quote_coin,
        &input_coin_deposit_plan,
        is_bid,
        ctx,
    );

    balance_manager.generate_proof_as_owner(ctx)
}

/// Executes the DEEP coin sourcing plan by acquiring coins from specified sources
/// Sources DEEP coins from user wallet and/or treasury reserves based on the deep plan
/// Deposits all acquired DEEP coins to the user's balance manager for order placement
///
/// Steps performed:
/// 1. Verifies the treasury has enough DEEP reserves
/// 2. Takes DEEP coins from user wallet when specified in the plan
/// 3. Takes DEEP coins from treasury reserves when needed
/// 4. Deposits all acquired DEEP coins to the balance manager
public(package) fun execute_deep_plan(
    treasury: &mut Treasury,
    balance_manager: &mut BalanceManager,
    deep_coin: &mut Coin<DEEP>,
    deep_plan: &DeepPlan,
    ctx: &mut TxContext,
) {
    treasury.verify_version();

    // Check if there is enough DEEP in the treasury reserves
    assert!(deep_plan.deep_reserves_cover_order, EInsufficientDeepReserves);

    // Take DEEP from wallet if needed
    if (deep_plan.from_user_wallet > 0) {
        let payment = deep_coin.split(deep_plan.from_user_wallet, ctx);
        balance_manager.deposit(payment, ctx);
    };

    // Take DEEP from treasury reserves if needed
    if (deep_plan.from_deep_reserves > 0) {
        let reserve_payment = treasury.split_deep_reserves(deep_plan.from_deep_reserves, ctx);
        balance_manager.deposit(reserve_payment, ctx);
    };
}

/// Executes the coverage fee charging plan by taking SUI coins from specified sources
///
/// Parameters:
/// - treasury: Main treasury object that will receive the fees
/// - balance_manager: User's balance manager to withdraw fees from
/// - sui_coin: User's SUI coins to take fees from
/// - fee_plan: Plan that specifies how much to take from each source
/// - ctx: Transaction context
///
/// Aborts:
/// - EInsufficientFee: If user cannot cover the fees
public(package) fun execute_coverage_fee_plan(
    treasury: &mut Treasury,
    balance_manager: &mut BalanceManager,
    sui_coin: &mut Coin<SUI>,
    fee_plan: &CoverageFeePlan,
    ctx: &mut TxContext,
) {
    treasury.verify_version();

    // Verify that the user has enough funds to cover the coverage fee
    assert!(fee_plan.user_covers_fee, EInsufficientFee);

    // Collect coverage fee from wallet if needed
    if (fee_plan.from_wallet > 0) {
        let fee = sui_coin.balance_mut().split(fee_plan.from_wallet);
        treasury.join_coverage_fee(fee);
    };

    // Collect coverage fee from balance manager if needed
    if (fee_plan.from_balance_manager > 0) {
        let fee = balance_manager.withdraw<SUI>(
            fee_plan.from_balance_manager,
            ctx,
        );
        treasury.join_coverage_fee(fee.into_balance());
    };
}

/// Executes a `ProtocolFeePlan` to collect Deeptrade fees from the user's
/// wallet and balance manager.
///
/// Taker fees are collected immediately into the Deeptrade's protocol fees. Maker
/// fees are added to an unsettled list for future settlement by the user or protocol.
///
/// Aborts if the plan indicates the user has insufficient funds.
public(package) fun execute_protocol_fee_plan<CoinType>(
    fee_manager: &mut FeeManager,
    balance_manager: &mut BalanceManager,
    coin: &mut Coin<CoinType>,
    order_info: &OrderInfo,
    fee_plan: &ProtocolFeePlan,
    ctx: &mut TxContext,
) {
    // Verify that the user has enough funds to cover the protocol fees
    assert!(fee_plan.user_covers_fee, EInsufficientFee);

    let mut taker_fee = balance::zero<CoinType>();

    // Join taker fee from wallet to total taker fee if needed
    if (fee_plan.taker_fee_from_wallet > 0) {
        let fee = coin.balance_mut().split(fee_plan.taker_fee_from_wallet);
        taker_fee.join(fee);
    };

    // Join taker fee from balance manager to total taker fee if needed
    if (fee_plan.taker_fee_from_balance_manager > 0) {
        let fee = balance_manager.withdraw<CoinType>(
            fee_plan.taker_fee_from_balance_manager,
            ctx,
        );
        taker_fee.join(fee.into_balance());
    };

    // Collect taker fee and emit event if needed
    let taker_fee_value = taker_fee.value();
    if (taker_fee_value > 0) {
        fee_manager.add_to_protocol_unsettled_fees(taker_fee, ctx);

        event::emit(TakerFeeCharged<CoinType> {
            pool_id: order_info.pool_id(),
            balance_manager_id: order_info.balance_manager_id(),
            order_id: order_info.order_id(),
            client_order_id: order_info.client_order_id(),
            taker_fee: taker_fee_value,
        });
    } else {
        // The taker fee is zero for fully maker orders (e.g., Post-Only, resting GTC),
        // or when the taker fee rate is zero
        taker_fee.destroy_zero();
    };

    let mut maker_fee = balance::zero<CoinType>();

    // Join maker fee from wallet to total maker fee if needed
    if (fee_plan.maker_fee_from_wallet > 0) {
        let fee = coin.balance_mut().split(fee_plan.maker_fee_from_wallet);
        maker_fee.join(fee);
    };

    // Join maker fee from balance manager to total maker fee if needed
    if (fee_plan.maker_fee_from_balance_manager > 0) {
        let fee = balance_manager.withdraw<CoinType>(
            fee_plan.maker_fee_from_balance_manager,
            ctx,
        );
        maker_fee.join(fee.into_balance());
    };

    if (maker_fee.value() > 0) {
        fee_manager.add_to_user_unsettled_fees(
            maker_fee,
            order_info,
            ctx,
        );
    } else {
        // Maker fee is zero for IOC/FOK orders (which don't act as makers), or when maker fee rate is zero,
        // or when the order is filled on creation
        maker_fee.destroy_zero();
    }
}

/// Executes the input coin deposit plan by transferring coins to the balance manager
/// Deposits required input coins from user wallet to balance manager based on the plan
/// Handles different coin types based on order type: quote coins for bid orders, base coins for ask orders
///
/// Steps performed:
/// 1. Verifies the user has enough input coins to satisfy the deposit requirements
/// 2. For bid orders: transfers quote coins from user wallet to balance manager
/// 3. For ask orders: transfers base coins from user wallet to balance manager
public(package) fun execute_input_coin_deposit_plan<BaseToken, QuoteToken>(
    balance_manager: &mut BalanceManager,
    base_coin: &mut Coin<BaseToken>,
    quote_coin: &mut Coin<QuoteToken>,
    deposit_plan: &InputCoinDepositPlan,
    is_bid: bool,
    ctx: &mut TxContext,
) {
    // Verify there are enough coins to satisfy the deposit requirements
    assert!(deposit_plan.user_has_enough_input_coin, EInsufficientInput);

    // Deposit coins from wallet if needed
    if (deposit_plan.from_user_wallet > 0) {
        if (is_bid) {
            // Quote coins for bid
            let payment = quote_coin.split(deposit_plan.from_user_wallet, ctx);
            balance_manager.deposit(payment, ctx);
        } else {
            // Base coins for ask
            let payment = base_coin.split(deposit_plan.from_user_wallet, ctx);
            balance_manager.deposit(payment, ctx);
        };
    };
}

// === Private Functions ===
/// Creates a coverage fee plan with no fees and user_covers_fee set to true
/// Used when no coverage fees are required
fun zero_coverage_fee_plan(): CoverageFeePlan {
    create_empty_coverage_fee_plan(true)
}

/// Creates a coverage fee plan with no fees and user_covers_fee set to false
/// Used when user doesn't have enough funds to cover fees
fun insufficient_coverage_fee_plan(): CoverageFeePlan {
    create_empty_coverage_fee_plan(false)
}

/// Creates a coverage fee plan with zero fees and specified user coverage status
///
/// Parameters:
/// - user_covers_fee: Whether the user can cover fees (true) or not (false)
///
/// Returns a CoverageFeePlan with zero fees from all sources
fun create_empty_coverage_fee_plan(user_covers_fee: bool): CoverageFeePlan {
    CoverageFeePlan {
        from_wallet: 0,
        from_balance_manager: 0,
        user_covers_fee,
    }
}

/// Creates a protocol fee plan with no fees and user_covers_fee set to true
/// Used when no protocol fees are required
fun zero_protocol_fee_plan(): ProtocolFeePlan {
    create_empty_protocol_fee_plan(true)
}

/// Creates a protocol fee plan with no fees and user_covers_fee set to false
/// Used when user doesn't have enough funds to cover protocol fees
fun insufficient_protocol_fee_plan(): ProtocolFeePlan {
    create_empty_protocol_fee_plan(false)
}

/// Creates a protocol fee plan with zero fees and specified user coverage status
///
/// Parameters:
/// - user_covers_fee: Whether the user can cover fees (true) or not (false)
///
/// Returns a ProtocolFeePlan with zero fees from all sources
fun create_empty_protocol_fee_plan(user_covers_fee: bool): ProtocolFeePlan {
    ProtocolFeePlan {
        taker_fee_from_wallet: 0,
        taker_fee_from_balance_manager: 0,
        maker_fee_from_wallet: 0,
        maker_fee_from_balance_manager: 0,
        user_covers_fee,
    }
}

// === Test-Only Functions ===
#[test_only]
public fun assert_deep_plan_eq(
    actual: DeepPlan,
    expected_from_wallet: u64,
    expected_from_balance_manager: u64,
    expected_from_treasury: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.from_user_wallet, expected_from_wallet);
    assert_eq!(actual.from_balance_manager, expected_from_balance_manager);
    assert_eq!(actual.from_deep_reserves, expected_from_treasury);
    assert_eq!(actual.deep_reserves_cover_order, expected_sufficient);
}

#[test_only]
public fun assert_coverage_fee_plan_eq(
    actual: CoverageFeePlan,
    expected_from_wallet: u64,
    expected_from_balance_manager: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.from_wallet, expected_from_wallet);
    assert_eq!(actual.from_balance_manager, expected_from_balance_manager);
    assert_eq!(actual.user_covers_fee, expected_sufficient);
}

#[test_only]
public fun assert_protocol_fee_plan_eq(
    actual: ProtocolFeePlan,
    expected_taker_fee_from_wallet: u64,
    expected_taker_fee_from_balance_manager: u64,
    expected_maker_fee_from_wallet: u64,
    expected_maker_fee_from_balance_manager: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.taker_fee_from_wallet, expected_taker_fee_from_wallet);
    assert_eq!(actual.taker_fee_from_balance_manager, expected_taker_fee_from_balance_manager);
    assert_eq!(actual.maker_fee_from_wallet, expected_maker_fee_from_wallet);
    assert_eq!(actual.maker_fee_from_balance_manager, expected_maker_fee_from_balance_manager);
    assert_eq!(actual.user_covers_fee, expected_sufficient);
}

#[test_only]
public fun assert_input_coin_deposit_plan_eq(
    actual: InputCoinDepositPlan,
    expected_from_user_wallet: u64,
    expected_sufficient: bool,
) {
    use std::unit_test::assert_eq;
    assert_eq!(actual.from_user_wallet, expected_from_user_wallet);
    assert_eq!(actual.user_has_enough_input_coin, expected_sufficient);
}

#[test_only]
public fun taker_fee_from_wallet(plan: &ProtocolFeePlan): u64 { plan.taker_fee_from_wallet }

#[test_only]
public fun taker_fee_from_balance_manager(plan: &ProtocolFeePlan): u64 {
    plan.taker_fee_from_balance_manager
}

#[test_only]
public fun maker_fee_from_wallet(plan: &ProtocolFeePlan): u64 { plan.maker_fee_from_wallet }

#[test_only]
public fun maker_fee_from_balance_manager(plan: &ProtocolFeePlan): u64 {
    plan.maker_fee_from_balance_manager
}

#[test_only]
public fun user_covers_fee(plan: &ProtocolFeePlan): bool { plan.user_covers_fee }

#[test_only]
public fun from_user_wallet(plan: &DeepPlan): u64 { plan.from_user_wallet }

#[test_only]
public fun from_deep_reserves(plan: &DeepPlan): u64 { plan.from_deep_reserves }

#[test_only]
public fun deep_reserves_cover_order(plan: &DeepPlan): bool {
    plan.deep_reserves_cover_order
}

#[test_only]
public fun from_user_wallet_icdp(plan: &InputCoinDepositPlan): u64 { plan.from_user_wallet }

#[test_only]
public fun user_has_enough_input_coin_icdp(plan: &InputCoinDepositPlan): bool {
    plan.user_has_enough_input_coin
}

#[test_only]
public fun from_wallet_cfp(plan: &CoverageFeePlan): u64 { plan.from_wallet }

#[test_only]
public fun from_balance_manager_cfp(plan: &CoverageFeePlan): u64 { plan.from_balance_manager }

#[test_only]
public fun user_covers_fee_cfp(plan: &CoverageFeePlan): bool { plan.user_covers_fee }
