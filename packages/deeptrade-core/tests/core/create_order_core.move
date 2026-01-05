#[test_only]
module deeptrade_core::create_order_core_tests;

use deeptrade_core::dt_order::{
    create_order_core,
    assert_deep_plan_eq,
    assert_coverage_fee_plan_eq,
    assert_input_coin_deposit_plan_eq,
    DeepPlan,
    CoverageFeePlan,
    InputCoinDepositPlan,
    EInvalidInputCoinType
};
use deeptrade_core::fee::calculate_deep_reserves_coverage_order_fee;
use deeptrade_core::helper::calculate_order_amount;
use std::unit_test::assert_eq;

// ===== Constants =====
// Token amounts
const AMOUNT_SMALL: u64 = 1_000; // 1,000
const AMOUNT_MEDIUM: u64 = 1_000_000; // 1 million
const AMOUNT_LARGE: u64 = 1_000_000_000; // 1 billion
const AMOUNT_HUGE: u64 = 1_000_000_000_000; // 1 trillion

// SUI per DEEP
const SUI_PER_DEEP: u64 = 37_815_000_000;

// ===== Helper Functions =====
/// Helper function to assert all three plans match expected values
#[test_only]
public fun assert_order_plans_eq(
    deep_plan: DeepPlan,
    coverage_fee_plan: CoverageFeePlan,
    input_coin_deposit_plan: InputCoinDepositPlan,
    // Expected values for DeepPlan
    expected_deep_from_wallet: u64,
    expected_deep_from_balance_manager: u64,
    expected_deep_from_reserves: u64,
    expected_deep_sufficient: bool,
    // Expected values for CoverageFeePlan
    expected_coverage_fee_from_wallet: u64,
    expected_coverage_fee_from_balance_manager: u64,
    expected_user_covers_fee: bool,
    // Expected values for InputCoinDepositPlan
    expected_deposit_from_wallet: u64,
    expected_deposit_sufficient: bool,
) {
    // Assert DeepPlan
    assert_deep_plan_eq(
        deep_plan,
        expected_deep_from_wallet,
        expected_deep_from_balance_manager,
        expected_deep_from_reserves,
        expected_deep_sufficient,
    );

    // Assert CoverageFeePlan
    assert_coverage_fee_plan_eq(
        coverage_fee_plan,
        expected_coverage_fee_from_wallet,
        expected_coverage_fee_from_balance_manager,
        expected_user_covers_fee,
    );

    // Assert InputCoinDepositPlan
    assert_input_coin_deposit_plan_eq(
        input_coin_deposit_plan,
        expected_deposit_from_wallet,
        expected_deposit_sufficient,
    );
}

// ===== Bid Order Tests =====

#[test]
public fun bid_order_sufficient_resources() {
    // Order parameters
    let quantity = 1_000_000_000_000;
    let price = 2_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL / 2;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_LARGE;

    let deep_in_wallet = AMOUNT_SMALL / 2;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = AMOUNT_LARGE;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid); // 2_000_000_000

    // For this test case we expect:
    // 1. DEEP: Half from wallet, half from balance manager
    // 2. No coverage fees because no treasury DEEP is used
    // 3. Token deposit: Remaining from wallet

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_required - balance_manager_deep, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        wallet_input_coin, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_with_treasury_deep() {
    // Order parameters
    let quantity = 100_000_000_000;
    let price = 1_500_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP in wallet or balance manager
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = 75_000_000;
    let balance_manager_input_coin = 75_000_000;

    let deep_in_wallet = AMOUNT_SMALL;
    let sui_in_wallet = 80_000_000;
    let wallet_input_coin = 80_000_000;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // For this test case we expect:
    // 1. DEEP: All from wallet and balance manager + some from treasury
    // 2. Coverage fee: First from balance manager, then from wallet if needed
    // 3. Token deposit: Remaining from wallet

    let deep_from_wallet = deep_in_wallet;
    let deposit_from_wallet = order_amount - balance_manager_input_coin;

    // Calculate coverage fee distribution
    let coverage_from_bm = if (balance_manager_sui >= coverage_fee) {
        coverage_fee
    } else {
        balance_manager_sui
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_from_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_from_wallet, // expected_coverage_fee_from_wallet
        coverage_from_bm, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        deposit_from_wallet, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_whitelisted_pool() {
    // Order parameters
    let quantity = 100_000;
    let price = 1_000_000;
    let is_bid = true;
    let is_pool_whitelisted = true; // Whitelisted pool!
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 0;
    let balance_manager_sui = AMOUNT_MEDIUM;
    let balance_manager_input_coin = AMOUNT_MEDIUM;

    let deep_in_wallet = 0;
    let sui_in_wallet = AMOUNT_MEDIUM;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // For this test case we expect:
    // 1. DEEP: None needed (whitelisted pool)
    // 2. Coverage fees: None (whitelisted pool)
    // 3. Token deposit: All from balance manager

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_coverage_fee_from_both_sources() {
    // Order parameters
    let quantity = 1_000_000_000_000;
    let price = 2_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let deep_in_wallet = AMOUNT_SMALL;
    let treasury_deep_reserves = AMOUNT_LARGE;

    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Set up a scenario where coverage fee needs to come from both sources
    // Put majority in balance manager to test prioritized usage
    let balance_manager_sui = (coverage_fee * 3) / 4;
    let sui_in_wallet = coverage_fee - balance_manager_sui;

    // Set up input coin balances
    let wallet_input_coin = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_LARGE;

    // Calculate expected coverage fee distribution
    let coverage_from_bm = if (balance_manager_sui >= coverage_fee) {
        coverage_fee
    } else {
        balance_manager_sui
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_from_wallet, // expected_coverage_fee_from_wallet
        coverage_from_bm, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        wallet_input_coin, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_insufficient_deep_no_treasury() {
    // Order parameters
    let quantity = 100_000_000_000;
    let price = 1_500_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP anywhere
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_LARGE;

    let deep_in_wallet = AMOUNT_SMALL;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = AMOUNT_LARGE;

    let treasury_deep_reserves = AMOUNT_SMALL; // Not enough DEEP in treasury

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        false, // expected_deep_sufficient (not enough DEEP)
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_quote_only_in_balance_manager() {
    // Order parameters
    let quantity = 1_000_000_000_000;
    let price = 2_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - all resources in balance manager
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_HUGE;

    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    let wallet_input_coin = 0;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_large_values() {
    // Order parameters with very large values
    let quantity = 1_000_000_000_000_000;
    let price = 1_000_000_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Make sure we have enough resources for this large order
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let deep_in_wallet = AMOUNT_SMALL;
    let treasury_deep_reserves = AMOUNT_LARGE;

    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Set up SUI balances to cover fees
    let balance_manager_sui = 0;
    let sui_in_wallet = coverage_fee;

    // Set up input coin balances
    let balance_manager_input_coin = 0;
    let wallet_input_coin = order_amount;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_fee, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        order_amount, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_exact_resources() {
    // Order parameters
    let quantity = 10_000_000_000;
    let price = 1_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - exactly what's needed
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 0;
    let balance_manager_sui = 0;
    let balance_manager_input_coin = 0;

    let deep_in_wallet = deep_required; // Exact amount in wallet
    let sui_in_wallet = 0; // No SUI needed since not using treasury DEEP
    let wallet_input_coin = calculate_order_amount(quantity, price, is_bid);

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_required, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        order_amount, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

// ===== Ask Order Tests =====

#[test]
public fun ask_order_sufficient_resources() {
    // Order parameters
    let quantity = 10_000_000_000;
    let price = 10_000_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL / 2;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = 100_000_000_000;

    let deep_in_wallet = AMOUNT_SMALL;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = 100_000_000_000;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    let deep_from_wallet = deep_required - balance_manager_deep;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // For this test case we expect:
    // 1. DEEP: Half from wallet, half from balance manager
    // 2. No coverage fees since user doesn't use treasury DEEP
    // 3. Token deposit: Full amount from wallet

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_from_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet (balance manager has enough)
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_whitelisted_pool() {
    // Order parameters
    let quantity = 10_000;
    let price = 1_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = true; // Whitelisted pool!
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 0;
    let balance_manager_sui = AMOUNT_MEDIUM;
    let balance_manager_input_coin = AMOUNT_MEDIUM;

    let deep_in_wallet = 0;
    let sui_in_wallet = AMOUNT_MEDIUM;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // For this test case we expect:
    // 1. DEEP: None needed (whitelisted pool)
    // 2. Coverage fees: None (whitelisted pool)
    // 3. Token deposit: All from balance manager

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_insufficient_deep_and_base() {
    // Order parameters
    let quantity = 20_564_999_999;
    let price = 40_000_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP anywhere
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL / 2;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_MEDIUM;

    let deep_in_wallet = AMOUNT_SMALL / 2;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_SMALL; // Not enough DEEP in treasury

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        false, // expected_deep_sufficient (not enough DEEP)
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        false, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_base_only_in_balance_manager() {
    // Order parameters
    let quantity = 10_000_000_000;
    let price = 1_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - base coins only in balance manager
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL - 50;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = quantity; // All base coins in balance manager

    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    let wallet_input_coin = 0;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    let deep_from_treasury = deep_required - balance_manager_deep;

    // Calculate coverage fee for treasury DEEP usage
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        coverage_fee, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_large_values() {
    // Order parameters with very large values
    let quantity = 1_000_000_000_000_000;
    let price = 1_000_000_000_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Make sure we have enough resources for this large order
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = 0;
    let balance_manager_sui = 0;
    let balance_manager_input_coin = 0;

    let deep_in_wallet = AMOUNT_MEDIUM - 100;
    let treasury_deep_reserves = AMOUNT_LARGE;

    let deep_from_treasury = deep_required - deep_in_wallet;

    // Calculate coverage fee for treasury DEEP usage
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // All resources from wallet
    let sui_in_wallet = coverage_fee;
    let wallet_input_coin = quantity;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_fee, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        quantity, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_exact_resources() {
    // Order parameters
    let quantity = 2_000_000;
    let price = 40_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Set up resources to exactly match what's needed
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 0;
    let balance_manager_sui = 0;
    let balance_manager_input_coin = 0;

    let deep_in_wallet = deep_required; // Exactly what's needed
    let sui_in_wallet = 0; // No SUI needed since not using treasury DEEP
    let wallet_input_coin = quantity; // Exactly what's needed

    let treasury_deep_reserves = 0;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_required, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        quantity, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_complex_distribution() {
    // Order parameters
    let quantity = 2_000_000;
    let price = 40_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - split between wallet and balance manager
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = deep_required / 2;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = 1_300_000;

    let deep_in_wallet = deep_required / 2;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = 700_000;

    let treasury_deep_reserves = deep_required;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        wallet_input_coin, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_insufficient_base() {
    // Order parameters
    let quantity = 70_000_000;
    let price = 1_000_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP to force using treasury DEEP
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL / 2;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = quantity - AMOUNT_SMALL - 1; // Not enough base coins

    let deep_in_wallet = AMOUNT_SMALL / 2;
    let treasury_deep_reserves = AMOUNT_MEDIUM;
    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate coverage fee for treasury DEEP usage
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Wallet has enough for fees but not enough for the deposit
    let sui_in_wallet = coverage_fee;
    let wallet_input_coin = AMOUNT_SMALL;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        coverage_fee, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        false, // expected_deposit_sufficient (not enough base coins)
    );
}

#[test]
public fun ask_order_with_treasury_deep() {
    // Order parameters
    let quantity = 70_000;
    let price = 54_000_000;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP in wallet or balance manager
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = 15_000;

    let deep_in_wallet = AMOUNT_SMALL;
    let treasury_deep_reserves = AMOUNT_MEDIUM;
    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate coverage fee for treasury DEEP usage
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Set up SUI and input coin balances
    let sui_in_wallet = coverage_fee;
    let wallet_input_coin = quantity - balance_manager_input_coin;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        coverage_fee, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        wallet_input_coin, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_coverage_fee_from_both_sources() {
    // Order parameters
    let quantity = 35_123_821;
    let price = 474_576_743;
    let is_bid = false; // Ask order
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances - not enough DEEP to avoid using treasury
    let deep_required = AMOUNT_MEDIUM;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_input_coin = quantity; // All base coins in balance manager
    let deep_in_wallet = AMOUNT_SMALL;
    let treasury_deep_reserves = AMOUNT_MEDIUM;

    let deep_from_treasury = deep_required - balance_manager_deep - deep_in_wallet;

    // Calculate coverage fee for treasury DEEP usage
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_treasury,
    );

    // Important: Make sure wallet doesn't have enough to cover all fees
    // We'll put 1/3 of the fee in wallet, 2/3 in balance manager
    let fee_in_wallet = coverage_fee / 3; // 1/3 of coverage fee in wallet
    let fee_in_balance_manager = coverage_fee - fee_in_wallet; // 2/3 of coverage fee in balance manager

    // Calculate coverage fee distribution
    let coverage_from_bm = if (fee_in_balance_manager >= coverage_fee) {
        coverage_fee
    } else {
        fee_in_balance_manager
    };
    let coverage_from_wallet = coverage_fee - coverage_from_bm;

    // Set up SUI balances to match fee distribution
    let balance_manager_sui = fee_in_balance_manager;
    let sui_in_wallet = fee_in_wallet;

    // Set up input coin balances - all base coins in balance manager
    let wallet_input_coin = 0;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_treasury, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_from_wallet, // expected_coverage_fee_from_wallet
        coverage_from_bm, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet (all from balance manager)
        true, // expected_deposit_sufficient
    );
}

// ===== Edge Cases =====

#[test]
public fun zero_quantity_order() {
    // Order parameters
    let quantity = 0; // Zero quantity
    let price = 1_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_MEDIUM;

    let deep_in_wallet = 0;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    // For this test case, order amount should be zero
    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        deep_required, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun zero_price_order() {
    // Order parameters
    let quantity = 10_000;
    let price = 0; // Zero price
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL;
    let balance_manager_sui = AMOUNT_LARGE;
    let balance_manager_input_coin = AMOUNT_MEDIUM;

    let deep_in_wallet = 0;
    let sui_in_wallet = AMOUNT_LARGE;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

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

    // For bid orders with zero price, order amount should be zero
    let order_amount = calculate_order_amount(quantity, price, is_bid);
    assert_eq!(order_amount, 0);

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        deep_required, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_input_coin_is_sui() {
    // Tests an ask order where the input coin is SUI.
    // Verifies that when the balance manager has enough SUI to cover the order amount,
    // a portion of it is first allocated to the coverage fee. The remaining balance
    // is then used for the order amount, and the deficit is covered by the wallet.
    // Order parameters
    let quantity = 1_000_000_000;
    let price = 1_000_000_000;
    let is_bid = false;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = true;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 0;
    let balance_manager_sui = 1_000_000_000;
    let balance_manager_input_coin = 1_000_000_000;

    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    // Make wallet sufficient to cover the deficit
    let wallet_input_coin = AMOUNT_LARGE;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    // Deep will be sourced from treasury, so a coverage fee is required
    let deep_from_reserves = deep_required;
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    );

    // The amount needed from the wallet is the order amount minus what's left
    // in the balance manager after the coverage fee is paid.
    let expected_deposit_from_wallet = order_amount - (balance_manager_input_coin - coverage_fee);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        deep_from_reserves, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        coverage_fee, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        expected_deposit_from_wallet, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_input_coin_is_deep() {
    // Tests an ask order where the input coin is DEEP.
    // Verifies that DEEP from the balance manager is first used for the deep requirement,
    // and the remainder is applied to the order amount. The wallet covers the rest.
    // Order parameters
    let quantity = 1_000_000_000;
    let price = 1_000_000_000;
    let is_bid = false;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = true;

    // Resource balances
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = 1_000_000_000;
    let balance_manager_sui = 0;
    let balance_manager_input_coin = 1_000_000_000;

    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    let wallet_input_coin = AMOUNT_MEDIUM;

    let treasury_deep_reserves = AMOUNT_MEDIUM;

    // Calculate expected values
    let order_amount = calculate_order_amount(quantity, price, is_bid);
    let deep_from_balance_manager = deep_required;
    let expected_deposit_from_wallet =
        order_amount - (balance_manager_deep - deep_from_balance_manager);

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        deep_required, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        expected_deposit_from_wallet, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test, expected_failure(abort_code = EInvalidInputCoinType)]
public fun invalid_input_coin_flags() {
    // Tests that create_order_core aborts if both input_coin_is_sui and
    // input_coin_is_deep are true.
    // Order parameters
    let quantity = 1_000_000_000;
    let price = 1_000_000_000;
    let is_bid = false;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = true;
    let input_coin_is_deep = true;

    // Resource balances (can be minimal since the function should abort early)
    let deep_required = 0;
    let balance_manager_deep = 0;
    let balance_manager_sui = 0;
    let balance_manager_input_coin = 0;
    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    let wallet_input_coin = 0;
    let treasury_deep_reserves = 0;
    let order_amount = calculate_order_amount(quantity, price, is_bid);

    create_order_core(
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
}

#[test]
public fun bid_order_sui_input_insufficient_wallet() {
    // Tests a bid order where the input coin is SUI and the wallet has insufficient
    // funds to cover the deposit after the balance manager pays the coverage fee.
    // Order parameters
    let quantity = 10_000_000;
    let price = 1_000_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = 1_000_000_000; // 1 SUI per DEEP for simplicity
    let input_coin_is_sui = true;
    let input_coin_is_deep = false;

    // Resource balances
    let deep_required = 1_000_000;
    let balance_manager_deep = 0;
    let deep_in_wallet = 0;
    let treasury_deep_reserves = AMOUNT_LARGE;

    // Trigger coverage fee
    let deep_from_reserves = deep_required;
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        sui_per_deep,
        deep_from_reserves,
    ); // Should be 1,000,000

    // BM can cover the fee, but not the whole order
    let balance_manager_sui = 2_000_000;
    let balance_manager_input_coin = balance_manager_sui;

    let order_amount = calculate_order_amount(quantity, price, is_bid); // 10,000,000
    let sui_left_in_bm = balance_manager_sui - coverage_fee; // 1,000,000
    let deposit_needed_from_wallet = order_amount - sui_left_in_bm; // 9,000,000

    // Wallet is insufficient
    let wallet_input_coin = deposit_needed_from_wallet - 1; // 8,999,999
    let sui_in_wallet = wallet_input_coin;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        deep_from_reserves, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        coverage_fee, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        false, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_deep_input_insufficient_wallet() {
    // Tests an ask order where the input coin is DEEP and the wallet has insufficient
    // funds to cover the deposit after the balance manager pays the deep requirement.
    // Order parameters
    let quantity = 10_000_000;
    let price = 1_000_000_000;
    let is_bid = false;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = true;

    // Resource balances
    let deep_required = 1_000_000;
    // BM can cover the deep requirement, but not the whole order
    let balance_manager_deep = 2_000_000;
    let balance_manager_input_coin = balance_manager_deep;
    let balance_manager_sui = 0;

    let order_amount = calculate_order_amount(quantity, price, is_bid); // 10,000,000
    let deep_left_in_bm = balance_manager_deep - deep_required; // 1,000,000
    let deposit_needed_from_wallet = order_amount - deep_left_in_bm; // 9,000,000

    // Wallet is insufficient
    let wallet_input_coin = deposit_needed_from_wallet - 1; // 8,999,999
    let deep_in_wallet = wallet_input_coin;
    let sui_in_wallet = 0;
    let treasury_deep_reserves = 0; // No treasury deep needed

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        deep_required, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        false, // expected_deposit_sufficient
    );
}

#[test]
public fun bid_order_sui_input_no_coverage_fee() {
    // Tests that when input coin is SUI and no coverage fee is needed,
    // the balance_manager_sui is not reduced for fees and is fully
    // available for the order deposit.
    // Order parameters
    let quantity = 1_000_000;
    let price = 1_000_000_000;
    let is_bid = true;
    let is_pool_whitelisted = false;
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = true;
    let input_coin_is_deep = false;

    // Resource balances
    // User has enough DEEP, so no treasury DEEP is needed
    let deep_required = AMOUNT_SMALL;
    let balance_manager_deep = AMOUNT_SMALL / 2;
    let deep_in_wallet = AMOUNT_SMALL / 2;
    let treasury_deep_reserves = AMOUNT_LARGE;

    // No coverage fee will be generated
    let deep_from_reserves = 0;
    let coverage_fee = 0;

    // BM has enough to cover the full order
    let order_amount = calculate_order_amount(quantity, price, is_bid); // 1,000,000
    let balance_manager_sui = order_amount;
    let balance_manager_input_coin = balance_manager_sui;

    let sui_in_wallet = 0;
    let wallet_input_coin = 0;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        deep_in_wallet, // expected_deep_from_wallet
        balance_manager_deep, // expected_deep_from_balance_manager
        deep_from_reserves, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        coverage_fee, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}

#[test]
public fun ask_order_deep_input_whitelisted_pool() {
    // Tests that when input coin is DEEP and the pool is whitelisted,
    // the balance_manager_deep is not reduced for deep requirements and
    // is fully available for the order deposit.
    // Order parameters
    let quantity = 1_000_000;
    let price = 1_000_000_000;
    let is_bid = false;
    let is_pool_whitelisted = true; // Whitelisted pool
    let sui_per_deep = SUI_PER_DEEP;
    let input_coin_is_sui = false;
    let input_coin_is_deep = true;

    // Resource balances
    // For a whitelisted pool, deep is not required.
    let deep_required = AMOUNT_SMALL; // This will be ignored

    // BM has enough to cover the full order
    let order_amount = calculate_order_amount(quantity, price, is_bid); // 1,000,000
    let balance_manager_deep = order_amount;
    let balance_manager_input_coin = balance_manager_deep;
    let balance_manager_sui = 0;

    let deep_in_wallet = 0;
    let sui_in_wallet = 0;
    let wallet_input_coin = 0;
    let treasury_deep_reserves = 0;

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

    assert_order_plans_eq(
        deep_plan,
        coverage_fee_plan,
        input_coin_deposit_plan,
        // DeepPlan expectations
        0, // expected_deep_from_wallet
        0, // expected_deep_from_balance_manager
        0, // expected_deep_from_reserves
        true, // expected_deep_sufficient
        // CoverageFeePlan expectations
        0, // expected_coverage_fee_from_wallet
        0, // expected_coverage_fee_from_balance_manager
        true, // expected_user_covers_fee
        // InputCoinDepositPlan expectations
        0, // expected_deposit_from_wallet
        true, // expected_deposit_sufficient
    );
}
