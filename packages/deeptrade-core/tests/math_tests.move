#[test_only]
module deeptrade_core::math_tests;

use deepbook::constants::max_u64;
use deeptrade_core::dt_math as math;
use std::unit_test::assert_eq;

/// This test demonstrates why using the scaled-math functions (`mul`, `div`)
/// for simple integer arithmetic is incorrect and loses precision, and why
/// `mul_div` is the correct tool for that job.
#[test]
fun demonstrates_precision_loss_of_old_method() {
    let val1 = 1000;
    let val2 = 10;
    let divisor = 30;

    // --- The Old, Incorrect Way using Scaled-Float Math ---
    // `math::mul` is for scaled numbers, so it divides by 10^9 internally.
    // This causes immediate truncation if the numbers aren't scaled.
    // (1000 * 10) / 1_000_000_000 = 10_000 / 1_000_000_000 = 0
    let intermediate_value = math::mul(val1, val2);
    assert_eq!(intermediate_value, 0);

    // The subsequent division will also be 0. The result is completely wrong.
    let old_way_result = math::div(intermediate_value, divisor);
    assert_eq!(old_way_result, 0);

    // --- The New, Correct Way using Integer Math ---
    // `math::mul_div` correctly calculates (val1 * val2) / divisor
    // (1000 * 10) / 30 = 10000 / 30 = 333
    let new_way_result = math::mul_div(val1, val2, divisor);
    assert_eq!(new_way_result, 333);
}

#[test]
fun known_values() {
    // Test case 1: No remainder
    assert_eq!(math::mul_div(100, 20, 5), 400);

    // Test case 2: With remainder, should round down
    // 2000 / 7 = 285.71...
    assert_eq!(math::mul_div(100, 20, 7), 285);

    // Test case 3: Larger numbers that are effectively scaled floats
    // (2.0 * 3.0) / 4.0 = 1.5
    assert_eq!(math::mul_div(2_000_000_000, 3_000_000_000, 4_000_000_000), 1_500_000_000);
}

#[test]
fun edge_cases() {
    // Test zero inputs
    assert_eq!(math::mul_div(0, 100, 10), 0);
    assert_eq!(math::mul_div(100, 0, 10), 0);

    // Test where numerator is smaller than denominator
    assert_eq!(math::mul_div(5, 5, 100), 0);

    // Test overflow prevention. This would fail if the implementation
    // did not cast to u128 internally. (u64_max * 2) would overflow u64.
    let max_u64 = max_u64();
    let actual = math::mul_div(max_u64, 2, 3);
    let expected = 12297829382473034410;
    assert_eq!(actual, expected);
}

#[test, expected_failure]
fun mul_div_by_zero_fails() {
    math::mul_div(100, 100, 0);
}

#[test]
fun rounding_direction() {
    let x = 100;
    let y = 20;

    // Test case where result has a remainder, expecting rounding down.
    // (100 * 20) / 7 = 2000 / 7 = 285.71... which should be 285.
    let z_rem = 7;
    assert_eq!(math::mul_div(x, y, z_rem), 285);

    // Test case where result has no remainder.
    // (100 * 20) / 5 = 2000 / 5 = 400.
    let z_no_rem = 5;
    assert_eq!(math::mul_div(x, y, z_no_rem), 400);
}

#[test]
fun documents_max_precision_loss() {
    // This test demonstrates that the precision loss from `mul_div` is always
    // less than 1 single unit of the final value.
    //
    // In any integer division `A / B`, the result can be broken down into:
    // - A whole number part (the quotient).
    // - A fractional part (the remainder / divisor).
    // For example, 10 / 3 is 3 with a remainder of 1. The exact result is 3 + 1/3.
    //
    // `mul_div(x, y, z)` calculates `(x * y) / z` using integer arithmetic,
    // which only keeps the whole number part (it truncates, or rounds down).
    // The precision loss is the fractional part that gets discarded: `((x * y) % z) / z`.
    //
    // Since the remainder `(x * y) % z` is always less than the divisor `z`, this
    // lost fraction is always a value between 0 (inclusive) and 1 (exclusive).
    // This test verifies this property by confirming that the rounded-up result
    // is at most 1 greater than the rounded-down result from `mul_div`.

    // Case 1: Remainder is 0. Loss is 0.
    let x1 = 100;
    let y1 = 10;
    let z1 = 5; // (100 * 10) / 5 = 200. Remainder is 0.
    let res1 = math::mul_div(x1, y1, z1);
    let res1_up = res1 + (if ((x1 as u128) * (y1 as u128) % (z1 as u128) != 0) 1 else 0);
    assert_eq!(res1, 200);
    assert_eq!(res1_up, 200); // No difference, no loss.

    // Case 2: A small remainder.
    // (100 * 10) / 6 = 166.66...
    let z2 = 6;
    let res2 = math::mul_div(x1, y1, z2);
    let res2_up = res2 + (if ((x1 as u128) * (y1 as u128) % (z2 as u128) != 0) 1 else 0);
    assert_eq!(res2, 166);
    assert_eq!(res2_up, 167); // Difference is 1. Loss is ~0.66.

    // Case 3: Maximum possible remainder.
    // The largest possible remainder for a divisor `z` is `z - 1`.
    // This creates the largest possible fractional part and thus the largest loss.
    // Let's calculate (99 * 1) / 100 = 0.99.
    let x3 = 99;
    let y3 = 1;
    let z3 = 100;
    let res3 = math::mul_div(x3, y3, z3);
    let res3_up = res3 + (if ((x3 as u128) * (y3 as u128) % (z3 as u128) != 0) 1 else 0);

    // `mul_div` rounds down to 0. The loss is 0.99.
    assert_eq!(res3, 0);
    // `mul_div_round_up` rounds up to 1.
    assert_eq!(res3_up, 1);

    // The true value is between `res3` and `res3_up`.
    // The difference between `mul_div` result and the true value is
    // always less than 1. This is confirmed by `res3_up` being at most `res3 + 1`.
    assert!(res3_up == res3 || res3_up == res3 + 1);
}

#[test]
fun mul_div_equivalent_for_scaled_numbers() {
    // This test demonstrates that for numbers that are already scaled up
    // to represent floating-point numbers, the old `div(mul(..))` pattern
    // and the new `mul_div(...)` function produce the same result.
    // This is because the scaling factor cancels out correctly in both cases.
    //
    // Let S = FLOAT_SCALING_U128
    // Old way: div(mul(x*S, y*S), z*S) = (((x*S * y*S) / S) * S) / (z*S) = (x*y/z)*S
    // New way: mul_div(x*S, y*S, z*S) = (x*S * y*S) / (z*S) = (x*y/z)*S
    //
    // This confirms `mul_div` is a safe replacement that also handles
    // regular integers correctly, unlike the old way.

    let scale = 1_000_000_000; // 10^9

    // Case 1: 2.5 * 3.5 / 1.25 = 7.0
    let x1 = 2_500_000_000; // 2.5 * scale
    let y1 = 3_500_000_000; // 3.5 * scale
    let z1 = 1_250_000_000; // 1.25 * scale

    let old_way_res1 = math::div(math::mul(x1, y1), z1);
    let new_way_res1 = math::mul_div(x1, y1, z1);

    assert_eq!(old_way_res1, 7_000_000_000); // 7.0 * scale
    assert_eq!(new_way_res1, old_way_res1);

    // Case 2: 100.0 * 0.5 / 2.0 = 25.0
    let x2 = 100 * scale;
    let y2 = 500_000_000; // 0.5 * scale
    let z2 = 2 * scale;

    let old_way_res2 = math::div(math::mul(x2, y2), z2);
    let new_way_res2 = math::mul_div(x2, y2, z2);

    assert_eq!(old_way_res2, 25 * scale);
    assert_eq!(new_way_res2, old_way_res2);
}

#[test, expected_failure]
fun mul_div_result_overflows_u64_fails() {
    // This test ensures that the `mul_div` function aborts if the final
    // result is too large to fit into a u64, preventing silent truncation.
    // We calculate (u64_max * 2) / 1, which should exceed u64::MAX.
    let max_u64 = max_u64();
    math::mul_div(max_u64, 2, 1);
}
