#[test_only]
module deeptrade_core::apply_protocol_swap_fee_tests;

use deeptrade_core::swap::apply_protocol_swap_fee;
use std::unit_test::assert_eq;

// === Test Constants ===
const SCALE: u64 = 1_000_000_000;

// === Test Case 1: base_quantity > 0 (swapping base for quote) ===

#[test]
fun base_quantity_greater_than_zero() {
    // Scenario: Swapping base tokens for quote tokens
    // - base_quantity = 1,000 tokens (swapping base for quote)
    // - quote_quantity = 0 (not swapping quote)
    // - Should apply fee to quote_out

    let base_quantity = 1_000 * SCALE; // 1,000 tokens
    let quote_quantity = 0; // Not swapping quote
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 500 * SCALE; // 500 tokens
    let taker_fee_rate = 1_000_000; // 0.1%
    let discount_rate = 200_000_000; // 20%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected calculations:
    // Base fee = calculate_fee_by_rate(500_000_000_000, 1_000_000) = 500_000_000_000 * 0.001 = 500_000_000
    // Discounted fee = apply_discount(500_000_000, 200_000_000) = 500_000_000 * (1 - 0.2) = 400_000_000
    // Final quote_out = 500_000_000_000 - 400_000_000 = 499_600_000_000
    // Final base_out = 1_000_000_000_000 (unchanged)

    assert_eq!(final_base_out, base_out); // Base output unchanged
    assert_eq!(final_quote_out, 499_600_000_000); // Quote output reduced by fee
}

// === Test Case 2: quote_quantity > 0 (swapping quote for base) ===

#[test]
fun quote_quantity_greater_than_zero() {
    // Scenario: Swapping quote tokens for base tokens
    // - base_quantity = 0 (not swapping base)
    // - quote_quantity = 1,000 tokens (swapping quote for base)
    // - Should apply fee to base_out

    let base_quantity = 0; // Not swapping base
    let quote_quantity = 1_000 * SCALE; // 1,000 tokens
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 500 * SCALE; // 500 tokens
    let taker_fee_rate = 1_000_000; // 0.1%
    let discount_rate = 200_000_000; // 20%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected calculations:
    // Base fee = calculate_fee_by_rate(1_000_000_000_000, 1_000_000) = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // Discounted fee = apply_discount(1_000_000_000, 200_000_000) = 1_000_000_000 * (1 - 0.2) = 800_000_000
    // Final base_out = 1_000_000_000_000 - 800_000_000 = 999_200_000_000
    // Final quote_out = 500_000_000_000 (unchanged)

    assert_eq!(final_base_out, 999_200_000_000); // Base output reduced by fee
    assert_eq!(final_quote_out, quote_out); // Quote output unchanged
}

// === Test Case 3: base_quantity = 0 AND quote_quantity = 0 (no swap direction) ===

#[test]
fun both_quantities_zero() {
    // Scenario: No swap direction specified
    // - base_quantity = 0 (not swapping base)
    // - quote_quantity = 0 (not swapping quote)
    // - Should return outputs unchanged (no fees applied)

    let base_quantity = 0; // Not swapping base
    let quote_quantity = 0; // Not swapping quote
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 500 * SCALE; // 500 tokens
    let taker_fee_rate = 1_000_000; // 0.1%
    let discount_rate = 200_000_000; // 20%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected: No fees applied since there's nothing to swap
    // Both outputs should remain unchanged

    assert_eq!(final_base_out, base_out); // Base output unchanged
    assert_eq!(final_quote_out, quote_out); // Quote output unchanged
}

// === Test Case 4: taker_fee_rate = 0 (no fees) ===

#[test]
fun zero_fee_rate() {
    // Scenario: Zero fee rate means no fees should be applied
    // - base_quantity > 0 (swapping base for quote)
    // - taker_fee_rate = 0 (no fees)
    // - Should return outputs unchanged

    let base_quantity = 1_000 * SCALE; // 1,000 tokens
    let quote_quantity = 0; // Not swapping quote
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 500 * SCALE; // 500 tokens
    let taker_fee_rate = 0; // 0% (no fees)
    let discount_rate = 200_000_000; // 20%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected: No fees applied since fee rate is zero
    // Both outputs should remain unchanged regardless of discount rate

    assert_eq!(final_base_out, base_out); // Base output unchanged
    assert_eq!(final_quote_out, quote_out); // Quote output unchanged
}

// === Test Case 5: discount_rate = 100% (full discount) ===

#[test]
fun full_discount_rate() {
    // Scenario: 100% discount means no fees should be applied
    // - base_quantity > 0 (swapping base for quote)
    // - discount_rate = 100% (full discount)
    // - Should return outputs unchanged

    let base_quantity = 1_000 * SCALE; // 1,000 tokens
    let quote_quantity = 0; // Not swapping quote
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 500 * SCALE; // 500 tokens
    let taker_fee_rate = 1_000_000; // 0.1%
    let discount_rate = 1_000_000_000; // 100%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected: No fees applied since discount is 100%
    // Both outputs should remain unchanged

    assert_eq!(final_base_out, base_out); // Base output unchanged
    assert_eq!(final_quote_out, quote_out); // Quote output unchanged
}

// === Test Case 6: zero outputs ===

#[test]
fun zero_outputs() {
    // Scenario: Zero outputs should handle gracefully
    // - base_quantity > 0 (swapping base for quote)
    // - quote_out = 0 (zero output)
    // - Should handle zero output without errors

    let base_quantity = 1_000 * SCALE; // 1,000 tokens
    let quote_quantity = 0; // Not swapping quote
    let base_out = 1_000 * SCALE; // 1,000 tokens
    let quote_out = 0; // Zero output
    let taker_fee_rate = 1_000_000; // 0.1%
    let discount_rate = 200_000_000; // 20%

    let (final_base_out, final_quote_out) = apply_protocol_swap_fee(
        taker_fee_rate,
        discount_rate,
        base_out,
        quote_out,
        base_quantity,
        quote_quantity,
    );

    // Expected: Fee calculation on zero should result in zero fee
    // Both outputs should remain unchanged

    assert_eq!(final_base_out, base_out); // Base output unchanged
    assert_eq!(final_quote_out, quote_out); // Quote output unchanged (still zero)
}
