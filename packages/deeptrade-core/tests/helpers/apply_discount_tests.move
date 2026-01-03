#[test_only]
module deeptrade_core::apply_discount_tests;

use deeptrade_core::dt_math as math;
use deeptrade_core::helper::{Self, EInvalidDiscountRate};
use std::unit_test::assert_eq;

/// Test that applying zero discount returns the original value
#[test]
fun zero_discount() {
    let value = 1000;
    let result = helper::apply_discount(value, 0);
    assert_eq!(result, value);
}

/// Test that applying full discount returns zero
#[test]
fun full_discount() {
    let value = 1000;
    let result = helper::apply_discount(value, 1_000_000_000); // 100% discount
    assert_eq!(result, 0);
}

/// Test standard discount calculation
#[test]
fun standard_discount() {
    let value = 1000;
    let discount_rate = 50_000_000; // 5% discount
    let result = helper::apply_discount(value, discount_rate);

    // Expected: 1000 * (1 - 0.05) = 1000 * 0.95 = 950
    assert_eq!(result, 950);
}

/// Test discount with maximum valid rate (99.9999999%)
#[test]
fun maximum_valid_discount() {
    let value = 1000;
    let discount_rate = 999_999_999; // Just under 100%
    let result = helper::apply_discount(value, discount_rate);

    // Expected: 1000 * (1 - 0.999999999) = 1000 * 0.000000001 = 0
    // Due to integer math, this rounds down to 0
    assert_eq!(result, 0);
}

/// Test with large values
#[test]
fun large_values() {
    let value = 1_000_000_000_000_000_000;
    let discount_rate = 200_000_000; // 20% discount
    let result = helper::apply_discount(value, discount_rate);

    // Expected: 1_000_000_000_000_000_000 * (1 - 0.20) = 1_000_000_000_000_000_000 * 0.80 = 800_000_000_000_000_000
    assert_eq!(result, 800_000_000_000_000_000);
}

/// Test with small values
#[test]
fun small_values() {
    let value = 10;
    let discount_rate = 50_000_000; // 5% discount
    let result = helper::apply_discount(value, discount_rate);

    // Expected: 10 * (1 - 0.05) = 10 * 0.95 = 9.5
    assert_eq!(result, 9);
}

/// Test with tiny values
#[test]
fun tiny_values() {
    let value = 1;
    let discount_rate = 500_000_000; // 50% discount
    let result = helper::apply_discount(value, discount_rate);

    // Expected: 1 * (1 - 0.50) = 1 * 0.50 = 0 (due to integer division)
    assert_eq!(result, 0);
}

/// Test mathematical verification of the discount calculation
#[test]
fun mathematical_verification() {
    let value = 1000;
    let discount_rate = 300_000_000; // 30% discount

    // Manual calculation to verify the function works correctly
    let discount_multiplier = 1_000_000_000 - discount_rate; // 700_000_000
    let expected = math::mul(value, discount_multiplier); // 1000 * 700_000_000 / 1_000_000_000 = 700

    let result = helper::apply_discount(value, discount_rate);
    assert_eq!(result, expected);
    assert_eq!(result, 700);
}

/// Test that discount rate greater than 100% causes abort
#[test, expected_failure(abort_code = EInvalidDiscountRate)]
fun invalid_discount_rate_aborts() {
    let value = 1000;
    let invalid_discount_rate = 1_000_000_001; // Greater than 100%
    helper::apply_discount(value, invalid_discount_rate);
}
