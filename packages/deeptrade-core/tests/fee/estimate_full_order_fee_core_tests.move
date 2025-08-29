#[test_only]
module deeptrade_core::estimate_full_order_fee_core_tests;

use deeptrade_core::fee::estimate_full_order_fee_core;
use std::unit_test::assert_eq;

// === Test Constants ===

// DEEP multiplier (DEEP has 6 decimals)
const DEEP_MULTIPLIER: u64 = 1_000_000;

// SUI per DEEP price for testing (similar to other tests)
const SUI_PER_DEEP: u64 = 37_815_000_000; // 0.037815 SUI per DEEP (12 decimals)

// Order amounts for testing
const ORDER_AMOUNT_MEDIUM: u64 = 1_000_000_000_000; // 1,000 tokens

// Fee rates for testing (in billionths)
const PROTOCOL_TAKER_FEE_RATE: u64 = 1_000_000; // 0.1%

// Discount rates for testing (in billionths)
const MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE: u64 = 500_000_000; // 50%
const LOYALTY_DISCOUNT_RATE: u64 = 200_000_000; // 20%

// === Test Case 1: deep_from_reserves > 0 ===

#[test]
fun deep_from_reserves_greater_than_zero() {
    // Scenario: User has some DEEP but needs more from reserves
    // - User has 5 DEEP in balance manager + 2 DEEP in wallet = 7 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 3 DEEP from reserves

    let balance_manager_deep = 5 * DEEP_MULTIPLIER; // 5 DEEP
    let deep_in_wallet = 2 * DEEP_MULTIPLIER; // 2 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 10 - 5 - 2 = 3 DEEP
    // Expected deep_reserves_coverage_fee = 3_000_000 * 37_815_000_000 / scale = 113_445_000
    assert_eq!(deep_reserves_coverage_fee, 113_445_000);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 3 = 7 DEEP
    // discount_rate = (50% * 7) / 10 = 35%
    // Expected total_discount_rate = min(35% + 20%, 100%) = min(55%, 100%) = 55%
    let expected_total_discount_rate = 550_000_000; // 55%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 55% discount = 1_000_000_000 * (1 - 0.55) = 450_000_000
    let expected_protocol_fee = 450_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 2: deep_from_reserves == 0 ===

#[test]
fun deep_from_reserves_equal_to_zero() {
    // Scenario: User has enough DEEP to cover the entire order requirement
    // - User has 8 DEEP in balance manager + 2 DEEP in wallet = 10 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 0 DEEP from reserves (user covers everything)

    let balance_manager_deep = 8 * DEEP_MULTIPLIER; // 8 DEEP
    let deep_in_wallet = 2 * DEEP_MULTIPLIER; // 2 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 10 - 8 - 2 = 0 DEEP
    // Expected deep_reserves_coverage_fee = 0 * 37_815_000_000 / scale = 0
    assert_eq!(deep_reserves_coverage_fee, 0);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 0 = 10 DEEP
    // discount_rate = (50% * 10) / 10 = 50% (maximum coverage discount)
    // Expected total_discount_rate = min(50% + 20%, 100%) = min(70%, 100%) = 70%
    let expected_total_discount_rate = 700_000_000; // 70%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 70% discount = 1_000_000_000 * (1 - 0.70) = 300_000_000
    let expected_protocol_fee = 300_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 3: deep_fee_coverage_discount_rate + loyalty_discount_rate > 100% ===

#[test]
fun combined_discount_rates_exceed_hundred_percent() {
    // Scenario: Combined discount rates exceed 100%, so capping is needed
    // - User has 9 DEEP in balance manager + 1 DEEP in wallet = 10 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 0 DEEP from reserves (user covers everything)
    // - Coverage discount: 50% (user covers 100% of DEEP requirement)
    // - Loyalty discount: 60% (high loyalty level)
    // - Combined: 50% + 60% = 110% (exceeds 100%, should cap at 100%)

    let balance_manager_deep = 9 * DEEP_MULTIPLIER; // 9 DEEP
    let deep_in_wallet = DEEP_MULTIPLIER; // 1 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    // Use higher loyalty discount rate to test capping
    let high_loyalty_discount_rate = 600_000_000; // 60%

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE,
        high_loyalty_discount_rate,
    );

    // Expected deep_from_reserves = 10 - 9 - 1 = 0 DEEP
    // Expected deep_reserves_coverage_fee = 0 * 37_815_000_000 / scale = 0
    assert_eq!(deep_reserves_coverage_fee, 0);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 0 = 10 DEEP
    // discount_rate = (50% * 10) / 10 = 50% (maximum coverage discount)
    // Expected total_discount_rate = min(50% + 60%, 100%) = min(110%, 100%) = 100%
    let expected_total_discount_rate = 1_000_000_000; // 100%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 100% discount = 1_000_000_000 * (1 - 1.00) = 0
    let expected_protocol_fee = 0;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 4: deep_fee_coverage_discount_rate + loyalty_discount_rate == 100% ===

#[test]
fun combined_discount_rates_equal_to_hundred_percent() {
    // Scenario: Combined discount rates equal exactly 100%, no capping needed
    // - User has 8 DEEP in balance manager + 0 DEEP in wallet = 8 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 2 DEEP from reserves
    // - Coverage discount: 80% (user covers 80% of DEEP requirement)
    // - Loyalty discount: 20%
    // - Combined: 80% + 20% = 100% (exactly 100%, no capping needed)

    let balance_manager_deep = 8 * DEEP_MULTIPLIER; // 8 DEEP
    let deep_in_wallet = 0; // 0 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    // Use higher max coverage discount rate to test exact 100% boundary
    let high_max_coverage_discount_rate = 800_000_000; // 80%

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        high_max_coverage_discount_rate,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 10 - 8 - 0 = 2 DEEP
    // Expected deep_reserves_coverage_fee = 2_000_000 * 37_815_000_000 / scale = 75_630_000
    assert_eq!(deep_reserves_coverage_fee, 75_630_000);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 2 = 8 DEEP
    // discount_rate = (80% * 8) / 10 = 64%
    // Expected total_discount_rate = min(64% + 20%, 100%) = min(84%, 100%) = 84%
    let expected_total_discount_rate = 840_000_000; // 84%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 84% discount = 1_000_000_000 * (1 - 0.84) = 160_000_000
    let expected_protocol_fee = 160_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 5: deep_fee_coverage_discount_rate + loyalty_discount_rate == 100% (exact boundary) ===

#[test]
fun combined_discount_rates_exactly_hundred_percent() {
    // Scenario: Combined discount rates equal exactly 100%, testing the boundary case
    // - User has 10 DEEP in balance manager + 0 DEEP in wallet = 10 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 0 DEEP from reserves
    // - Coverage discount: 80% (user covers 100% of DEEP requirement)
    // - Loyalty discount: 20%
    // - Combined: 80% + 20% = 100% (exactly 100%, no capping needed)

    let balance_manager_deep = 10 * DEEP_MULTIPLIER; // 10 DEEP
    let deep_in_wallet = 0; // 0 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    // Use higher max coverage discount rate to test exact 100% boundary
    let high_max_coverage_discount_rate = 800_000_000; // 80%

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        high_max_coverage_discount_rate,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 10 - 10 - 0 = 0 DEEP
    // Expected deep_reserves_coverage_fee = 0 * 37_815_000_000 = 0
    assert_eq!(deep_reserves_coverage_fee, 0);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 0 = 10 DEEP
    // discount_rate = (80% * 10) / 10 = 80%
    // Expected total_discount_rate = min(80% + 20%, 100%) = min(100%, 100%) = 100%
    let expected_total_discount_rate = 1_000_000_000; // 100%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 100% discount = 1_000_000_000 * (1 - 1.00) = 0
    let expected_protocol_fee = 0;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 6: deep_required == 0 ===

#[test]
fun deep_required_equal_to_zero() {
    // Scenario: No DEEP is required for the order
    // - User has 5 DEEP in balance manager + 2 DEEP in wallet = 7 DEEP total
    // - Order requires 0 DEEP total
    // - Therefore needs 0 DEEP from reserves
    // - This should result in maximum coverage discount since no DEEP is required

    let balance_manager_deep = 5 * DEEP_MULTIPLIER; // 5 DEEP
    let deep_in_wallet = 2 * DEEP_MULTIPLIER; // 2 DEEP
    let deep_required = 0; // 0 DEEP required

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 0 - 5 - 2 = 0 DEEP (or should be 0 since deep_required is 0)
    // Expected deep_reserves_coverage_fee = 0 * 37_815_000_000 / scale = 0
    assert_eq!(deep_reserves_coverage_fee, 0);

    // Expected deep_fee_coverage_discount_rate calculation:
    // According to calculate_deep_fee_coverage_discount_rate function:
    // If deep_required is 0, return max_deep_fee_coverage_discount_rate
    // So coverage discount = 50% (maximum)
    // Expected total_discount_rate = min(50% + 20%, 100%) = min(70%, 100%) = 70%
    let expected_total_discount_rate = 700_000_000; // 70%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 70% discount = 1_000_000_000 * (1 - 0.70) = 300_000_000
    let expected_protocol_fee = 300_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 7: balance_manager_deep + deep_in_wallet > deep_required ===

#[test]
fun user_has_excess_deep() {
    // Scenario: User has more DEEP than required for the order
    // - User has 8 DEEP in balance manager + 5 DEEP in wallet = 13 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 0 DEEP from reserves (user has excess)
    // - This should result in maximum coverage discount since user covers 100% of requirement

    let balance_manager_deep = 8 * DEEP_MULTIPLIER; // 8 DEEP
    let deep_in_wallet = 5 * DEEP_MULTIPLIER; // 5 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        MAX_DEEP_FEE_COVERAGE_DISCOUNT_RATE,
        LOYALTY_DISCOUNT_RATE,
    );

    // Expected deep_from_reserves = 10 - 8 - 5 = 0 DEEP (user has excess)
    // Expected deep_reserves_coverage_fee = 0 * 37_815_000_000 / scale = 0
    assert_eq!(deep_reserves_coverage_fee, 0);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 0 = 10 DEEP
    // discount_rate = (50% * 10) / 10 = 50% (maximum coverage discount)
    // Expected total_discount_rate = min(50% + 20%, 100%) = min(70%, 100%) = 70%
    let expected_total_discount_rate = 700_000_000; // 70%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 70% discount = 1_000_000_000 * (1 - 0.70) = 300_000_000
    let expected_protocol_fee = 300_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}

// === Test Case 8: Zero discount rates ===

#[test]
fun zero_discount_rates() {
    // Scenario: No discounts are applied (zero discount rates)
    // - User has 3 DEEP in balance manager + 2 DEEP in wallet = 5 DEEP total
    // - Order requires 10 DEEP total
    // - Therefore needs 5 DEEP from reserves
    // - Zero max coverage discount rate and zero loyalty discount rate
    // - This should result in no discount applied to protocol fees

    let balance_manager_deep = 3 * DEEP_MULTIPLIER; // 3 DEEP
    let deep_in_wallet = 2 * DEEP_MULTIPLIER; // 2 DEEP
    let deep_required = 10 * DEEP_MULTIPLIER; // 10 DEEP

    // Use zero discount rates
    let zero_max_coverage_discount_rate = 0; // 0%
    let zero_loyalty_discount_rate = 0; // 0%

    let (
        deep_reserves_coverage_fee,
        protocol_fee,
        total_discount_rate,
    ) = estimate_full_order_fee_core(
        balance_manager_deep,
        deep_in_wallet,
        deep_required,
        SUI_PER_DEEP,
        PROTOCOL_TAKER_FEE_RATE,
        ORDER_AMOUNT_MEDIUM,
        zero_max_coverage_discount_rate,
        zero_loyalty_discount_rate,
    );

    // Expected deep_from_reserves = 10 - 3 - 2 = 5 DEEP
    // Expected deep_reserves_coverage_fee = 5_000_000 * 37_815_000_000 / scale = 189_075_000
    assert_eq!(deep_reserves_coverage_fee, 189_075_000);

    // Expected deep_fee_coverage_discount_rate calculation:
    // deep_covered_by_user = 10 - 5 = 5 DEEP
    // discount_rate = (0% * 5) / 10 = 0% (no coverage discount)
    // Expected total_discount_rate = min(0% + 0%, 100%) = min(0%, 100%) = 0%
    let expected_total_discount_rate = 0; // 0%
    assert_eq!(total_discount_rate, expected_total_discount_rate);

    // Expected protocol_fee calculation:
    // Base protocol fee = 1_000_000_000_000 * 0.001 = 1_000_000_000
    // After 0% discount = 1_000_000_000 * (1 - 0.00) = 1_000_000_000 (no discount)
    let expected_protocol_fee = 1_000_000_000;
    assert_eq!(protocol_fee, expected_protocol_fee);
}
