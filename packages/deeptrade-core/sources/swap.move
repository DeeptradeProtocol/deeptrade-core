module deeptrade_core::swap;

use deepbook::pool::Pool;
use deeptrade_core::fee::{calculate_fee_by_rate, TradingFeeConfig};
use deeptrade_core::helper::apply_discount;
use deeptrade_core::loyalty::LoyaltyProgram;
use deeptrade_core::treasury::Treasury;
use sui::balance::Balance;
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::event;

// === Errors ===
/// Error when the final output amount is below the user's specified minimum
const EInsufficientOutputAmount: u64 = 1;
const EInsufficientCoinBalance: u64 = 2;

// === Events ===
public struct SwapExecuted<phantom BaseAsset, phantom QuoteAsset> has copy, drop {
    treasury_id: ID,
    pool_id: ID,
    base_to_quote: bool,
    input_amount: u64,
    output_amount: u64,
    input_remainder: u64,
    fee_amount: u64,
    client_id: u64,
}

// === Public-Mutative Functions ===
/// Swaps a specific amount of base tokens for quote tokens using input fee model.
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version and join protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: The loyalty program for fee discounts
/// - pool: The DeepBook liquidity pool for this trading pair
/// - base_in: The base tokens being provided for the swap
/// - min_quote_out: Minimum amount of quote tokens to receive (slippage protection)
/// - client_id: Client-provided identifier
/// - clock: Clock object for timestamp information
/// - ctx: Transaction context
///
/// Returns:
/// - (Coin<BaseToken>, Coin<QuoteToken>): Any unused base tokens and the received quote tokens
///
/// Flow:
/// 1. Executes swap through DeepBook
/// 2. Processes Deeptrade fees
/// 3. Validates minimum output amount meets user requirements
/// 4. Returns remaining base and received quote tokens
public fun swap_exact_base_for_quote_input_fee<BaseToken, QuoteToken>(
    treasury: &mut Treasury,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    base_in: Coin<BaseToken>,
    min_quote_out: u64,
    client_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    let base_quantity = base_in.value();

    // Execute swap through DeepBook's native swap function with input fee model
    let (base_remainder, quote_out, deep_remainder) = pool.swap_exact_quantity(
        base_in,
        coin::zero(ctx),
        coin::zero(ctx), // No DEEP payment needed for input fee model
        min_quote_out,
        clock,
        ctx,
    );
    // `deep_remainder` is empty since no DEEP was provided for this input-fee swap
    deep_remainder.destroy_zero();

    // Apply Deeptrade protocol fees to the output
    let mut result_quote = quote_out;
    let (taker_fee_rate, _) = trading_fee_config
        .get_pool_fee_config(pool)
        .input_coin_fee_type_rates();

    let discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());
    let fee_balance = charge_protocol_swap_fee(&mut result_quote, taker_fee_rate, discount_rate);
    let fee_amount = fee_balance.value();
    treasury.join_protocol_fee(fee_balance);

    // Verify that the final output after Deeptrade fees still meets the user's minimum requirement
    validate_minimum_output(&result_quote, min_quote_out);

    event::emit(SwapExecuted<BaseToken, QuoteToken> {
        treasury_id: object::id(treasury),
        pool_id: object::id(pool),
        base_to_quote: true,
        input_amount: base_quantity,
        output_amount: result_quote.value(),
        input_remainder: base_remainder.value(),
        fee_amount,
        client_id,
    });

    (base_remainder, result_quote)
}

/// Swaps a specific amount of quote tokens for base tokens using input fee model.
///
/// Parameters:
/// - treasury: The Deeptrade treasury instance to verify the package version and join protocol fees
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: The loyalty program for fee discounts
/// - pool: The DeepBook liquidity pool for this trading pair
/// - quote_in: The quote tokens being provided for the swap
/// - min_base_out: Minimum amount of base tokens to receive (slippage protection)
/// - client_id: Client-provided identifier
/// - clock: Clock object for timestamp information
/// - ctx: Transaction context
///
/// Returns:
/// - (Coin<BaseToken>, Coin<QuoteToken>): The received base tokens and any unused quote tokens
///
/// Flow:
/// 1. Executes swap through DeepBook
/// 2. Processes Deeptrade fees
/// 3. Validates minimum output amount meets user requirements
/// 4. Returns received base and remaining quote tokens
public fun swap_exact_quote_for_base_input_fee<BaseToken, QuoteToken>(
    treasury: &mut Treasury,
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &mut Pool<BaseToken, QuoteToken>,
    quote_in: Coin<QuoteToken>,
    min_base_out: u64,
    client_id: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<BaseToken>, Coin<QuoteToken>) {
    treasury.verify_version();

    let quote_quantity = quote_in.value();

    // Execute swap through DeepBook's native swap function with input fee model
    let (base_out, quote_remainder, deep_remainder) = pool.swap_exact_quantity(
        coin::zero(ctx),
        quote_in,
        coin::zero(ctx), // No DEEP payment needed for input fee model
        min_base_out,
        clock,
        ctx,
    );
    // `deep_remainder` is empty since no DEEP was provided for this input-fee swap
    deep_remainder.destroy_zero();

    // Apply Deeptrade protocol fees to the output
    let mut result_base = base_out;
    let (taker_fee_rate, _) = trading_fee_config
        .get_pool_fee_config(pool)
        .input_coin_fee_type_rates();
    let discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());
    let fee_balance = charge_protocol_swap_fee(&mut result_base, taker_fee_rate, discount_rate);
    let fee_amount = fee_balance.value();
    treasury.join_protocol_fee(fee_balance);

    // Verify that the final output after Deeptrade fees still meets the user's minimum requirement
    validate_minimum_output(&result_base, min_base_out);

    event::emit(SwapExecuted<BaseToken, QuoteToken> {
        treasury_id: object::id(treasury),
        pool_id: object::id(pool),
        base_to_quote: false,
        input_amount: quote_quantity,
        output_amount: result_base.value(),
        input_remainder: quote_remainder.value(),
        fee_amount,
        client_id,
    });

    (result_base, quote_remainder)
}

// === Public-View Functions ===
/// Calculate the expected output quantity accounting for both DeepBook fees and Deeptrade fees
/// Uses input coin fee model instead of DEEP
///
/// Parameters:
/// - trading_fee_config: Trading fee configuration object
/// - loyalty_program: The loyalty program for fee discounts
/// - pool: The DeepBook liquidity pool for this trading pair
/// - base_quantity: Amount of base tokens to swap (set to 0 if swapping quote)
/// - quote_quantity: Amount of quote tokens to swap (set to 0 if swapping base)
/// - clock: Clock object for timestamp information
///
/// Returns:
/// - (u64, u64, u64): Tuple containing:
///   - Expected base token output
///   - Expected quote token output
///   - Required DEEP amount for transaction (always 0 for input-fee model)
///
/// Flow:
/// 1. Gets raw output quantities from DeepBook using input fee model
/// 2. Applies Deeptrade protocol fees to the appropriate output amount based on swap direction
/// 3. Returns final expected output quantities
public fun get_quantity_out_input_fee<BaseToken, QuoteToken>(
    trading_fee_config: &TradingFeeConfig,
    loyalty_program: &LoyaltyProgram,
    pool: &Pool<BaseToken, QuoteToken>,
    base_quantity: u64,
    quote_quantity: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (u64, u64, u64) {
    // Get the raw output quantities from DeepBook using input fee model
    // This method can return zero values in case input quantities don't meet the minimum lot size
    let (base_out, quote_out, deep_required) = pool.get_quantity_out_input_fee(
        base_quantity,
        quote_quantity,
        clock,
    );

    // Get the taker fee rate for the pool
    let (taker_fee_rate, _) = trading_fee_config
        .get_pool_fee_config(pool)
        .input_coin_fee_type_rates();

    let discount_rate = loyalty_program.get_user_discount_rate(ctx.sender());

    let (base_out, quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    (base_out, quote_out, deep_required)
}

// === Public-Package Functions ===
/// Calculates and applies Deeptrade protocol fee to the output quantity from a DeepBook swap.
/// Handles fee calculation and application for both base-to-quote and quote-to-base swaps.
///
/// Parameters:
/// - taker_fee_rate: The taker fee rate to apply to the output quantities
/// - discount_rate: The discount rate to apply to the calculated fees
/// - base_out: Mutable base token output quantity before fees
/// - quote_out: Mutable quote token output quantity before fees
/// - base_quantity: Input quantity of base tokens (0 if swapping quote)
/// - quote_quantity: Input quantity of quote tokens (0 if swapping base)
///
/// Returns:
/// - (u64, u64): Tuple containing:
///   - Final base token output after fees
///   - Final quote token output after fees
public(package) fun apply_protocol_swap_fee(
    taker_fee_rate: u64,
    discount_rate: u64,
    mut base_out: u64,
    mut quote_out: u64,
    base_quantity: u64,
    quote_quantity: u64,
): (u64, u64) {
    // Apply protocol fee to the output quantity
    // If base_quantity > 0, we're swapping base for quote, so apply fee to quote_out
    // If quote_quantity > 0, we're swapping quote for base, so apply fee to base_out
    if (base_quantity > 0) {
        // Swapping base for quote, apply fee to quote_out
        let mut fee_amount = calculate_fee_by_rate(quote_out, taker_fee_rate);
        fee_amount = apply_discount(fee_amount, discount_rate);
        quote_out = quote_out - fee_amount;
    } else if (quote_quantity > 0) {
        // Swapping quote for base, apply fee to base_out
        let mut fee_amount = calculate_fee_by_rate(base_out, taker_fee_rate);
        fee_amount = apply_discount(fee_amount, discount_rate);
        base_out = base_out - fee_amount;
    };

    (base_out, quote_out)
}

// === Private Functions ===
/// Validates that a coin's value meets the minimum required amount
/// Aborts with EInsufficientOutputAmount if the check fails
///
/// Parameters:
/// - coin: The coin to validate
/// - minimum: The minimum required value
fun validate_minimum_output<CoinType>(coin: &Coin<CoinType>, minimum: u64) {
    assert!(coin.value() >= minimum, EInsufficientOutputAmount);
}

/// Charges Deeptrade protocol swap fees on a coin and returns the fee amount as a Balance.
///
/// Parameters:
/// - coin: The coin to charge fee from
/// - fee_bps: The fee rate in billionths
/// - discount_rate: The discount rate to apply to the calculated fees
///
/// Returns:
/// - Balance<CoinType>: The fee amount as a Balance object
fun charge_protocol_swap_fee<CoinType>(
    coin: &mut Coin<CoinType>,
    fee_bps: u64,
    discount_rate: u64,
): Balance<CoinType> {
    let coin_balance = coin.balance_mut();
    let coin_value = coin_balance.value();
    let mut fee = calculate_fee_by_rate(coin_value, fee_bps);
    fee = apply_discount(fee, discount_rate);

    // Safety check: fee cannot exceed coin value since fee rate is capped below 100%
    assert!(coin_value >= fee, EInsufficientCoinBalance);

    coin_balance.split(fee)
}
