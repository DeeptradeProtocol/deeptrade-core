#[test_only]
module deeptrade_core::calculate_input_coin_deepbook_fee_tests;

use deeptrade_core::fee::calculate_input_coin_deepbook_fee;
use std::u64;
use std::unit_test::assert_eq;

#[test]
/// Test when amount is zero, result should be zero
fun zero_amount() {
    // When amount is zero, result should be zero regardless of taker_fee
    let fee = calculate_input_coin_deepbook_fee(0, 100_000);
    assert_eq!(fee, 0);
}

#[test]
/// Test when taker_fee is zero, result should be zero
fun zero_taker_fee() {
    // When taker_fee is zero, result should be zero regardless of amount
    let fee = calculate_input_coin_deepbook_fee(1_000_000, 0);
    assert_eq!(fee, 0);
}

#[test]
/// Test with typical values
fun happy_path() {
    let amount = 1_000_000_000; // 1,000,000,000 (e.g. 1 SUI)
    let taker_fee = 1_000_000; // 0.1% in billionths, from deepbook::constants::taker_fee()

    // Expected calculation:
    // fee_penalty_multiplier = 1_250_000_000; // 1.25, from deepbook::constants::fee_penalty_multiplier()
    // input_coin_fee_rate = 1_000_000 * 1.25 = 1_250_000
    // input_coin_fee = 1_000_000_000 * 1_250_000 / 1_000_000_000 = 1_250_000
    let expected_fee = 1_250_000;

    let calculated_fee = calculate_input_coin_deepbook_fee(amount, taker_fee);
    assert_eq!(calculated_fee, expected_fee);
}

#[test]
/// Test for precision and rounding behavior
fun rounding_behavior() {
    let amount = 999; // 0.000000999 SUI
    let taker_fee = 1_000_000; // 0.1%

    // Expected calculation:
    // fee_penalty_multiplier = 1_250_000_000; // 1.25
    // input_coin_fee_rate = (1_000_000 * 1_250_000_000) / 1_000_000_000 = 1_250_000
    // input_coin_fee = (999 * 1_250_000) / 1_000_000_000 = 1_248_750_000 / 1_000_000_000 = 1.24875
    // With integer division, this rounds down to 1.
    let expected_fee = 1;

    let calculated_fee = calculate_input_coin_deepbook_fee(amount, taker_fee);
    assert_eq!(calculated_fee, expected_fee);
}

#[test]
/// Test with a very small amount (1)
fun smallest_amount() {
    let amount = 1;
    let taker_fee = 1_000_000; // 0.1%

    // Expected calculation:
    // input_coin_fee_rate = 1_250_000
    // input_coin_fee = (1 * 1_250_000) / 1_000_000_000 = 0.00125
    // With integer division, this rounds down to 0.
    let expected_fee = 0;

    let calculated_fee = calculate_input_coin_deepbook_fee(amount, taker_fee);
    assert_eq!(calculated_fee, expected_fee);
}

#[test, expected_failure]
/// Test with maximum u64 amount to check for overflow.
/// This is expected to fail with an arithmetic overflow.
fun max_amount_overflow() {
    // We use a taker_fee high enough to cause an overflow when multiplied by amount.
    // The result of the fee calculation will exceed u64::MAX.
    calculate_input_coin_deepbook_fee(
        u64::max_value!(), // u64::MAX
        1_000_000_000, // 100%
    );
}

#[test, expected_failure]
/// Test with a large taker_fee to check for overflow during the
/// intermediate calculation of `input_coin_fee_rate`.
/// This is expected to fail with an arithmetic overflow.
fun max_taker_fee_overflow() {
    // This test uses a large taker_fee that will cause an overflow
    // inside the math::mul function when calculating the penalized fee rate.
    calculate_input_coin_deepbook_fee(
        1_000_000_000,
        u64::max_value!(), // u64::MAX
    );
}
