#[test_only]
module deeptrade_core::math_tests {
    use deeptrade_core::math;
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
        let max_u64 = 18446744073709551615;
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
        let z_rem = 7; // 2000 / 7 = 285.71...

        // Test rounding down
        assert_eq!(math::mul_div(x, y, z_rem), 285);

        // Test rounding up
        assert_eq!(math::mul_div_round_up(x, y, z_rem), 286);

        // Test case where result has no remainder
        let z_no_rem = 5; // 2000 / 5 = 400
        assert_eq!(math::mul_div(x, y, z_no_rem), 400);
        assert_eq!(math::mul_div_round_up(x, y, z_no_rem), 400);
    }
}