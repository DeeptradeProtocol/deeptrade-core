#[test_only]
module deeptrade_core::swap_input_fee_tests;

use deepbook::balance_manager_tests::USDC;
use deepbook::pool::{Pool, EInvalidQuantityIn};
use deeptrade_core::fee::TradingFeeConfig;
use deeptrade_core::get_quantity_out_input_fee_tests::setup_test_environment;
use deeptrade_core::loyalty::{Self, LoyaltyAdminCap, LoyaltyProgram};
use deeptrade_core::swap::{
    swap_exact_base_for_quote_input_fee,
    swap_exact_quote_for_base_input_fee,
    EInsufficientOutputAmount
};
use deeptrade_core::treasury;
use sui::clock::Clock;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared, take_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

// Test loyalty levels
const LEVEL_SILVER: u8 = 2;

// Test amounts and scaling
const SCALE: u64 = 1_000_000_000; // 100% in billionths
const BASE_AMOUNT: u64 = 5 * SCALE; // 5 SUI
const QUOTE_AMOUNT: u64 = 2 * SCALE; // 2 USDC
const MIN_QUOTE_OUT: u64 = SCALE; // 1 USDC minimum
const MIN_BASE_OUT: u64 = 1; // 1 nano SUI minimum

// === Test Case 1: Successful base-to-quote swap ===

#[test]
fun base_to_quote_success() {
    let client_id = 12345;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create base coin for ALICE
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(BASE_AMOUNT, scenario.ctx());

    // Execute the swap
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_remainder, quote_out) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin,
            MIN_QUOTE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Verify results
        assert!(base_remainder.value() >= 0); // May have remainder or be empty
        assert!(quote_out.value() >= MIN_QUOTE_OUT); // Must meet minimum requirement
        assert!(quote_out.value() > 0); // Should get some quote tokens

        // Cleanup
        destroy(base_remainder);
        destroy(quote_out);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 2: Successful quote-to-base swap ===

#[test]
fun quote_to_base_success() {
    let client_id = 67890;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create quote coin for ALICE
    scenario.next_tx(ALICE);
    let quote_coin = mint_for_testing<USDC>(QUOTE_AMOUNT, scenario.ctx());

    // Execute the swap
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin,
            MIN_BASE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Verify results
        assert!(base_out.value() >= MIN_BASE_OUT); // Must meet minimum requirement
        assert!(base_out.value() > 0); // Should get some base tokens
        assert!(quote_remainder.value() >= 0); // May have remainder or be empty

        // Cleanup
        destroy(base_out);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 3: Minimum output validation failure ===

#[test, expected_failure(abort_code = EInsufficientOutputAmount)]
fun minimum_output_validation_failure() {
    let client_id = 99999;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create base coin for ALICE
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(BASE_AMOUNT, scenario.ctx());

    // Execute the swap with a minimum output that will fail after high fees
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        // Get the exact output from DeepBook using get_quantity_out_input_fee
        let (_, deepbook_quote_out, _) = pool.get_quantity_out_input_fee(
            BASE_AMOUNT, // base_quantity
            0, // quote_quantity (0 for base-to-quote swap)
            &clock,
        );

        // Set minimum to slightly less than what DeepBook gives us
        // This ensures DeepBook passes but our validation fails after fees
        let impossible_min_quote_out = deepbook_quote_out - 1; // 1 nano USDC less than DeepBook output

        let (base_remainder, quote_out) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin,
            impossible_min_quote_out,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // This should never be reached - the function should abort above
        // But if it doesn't abort, we need to clean up the coins
        destroy(base_remainder);
        destroy(quote_out);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 4: Quote-to-base minimum output validation failure ===

#[test, expected_failure(abort_code = EInsufficientOutputAmount)]
fun quote_to_base_minimum_output_validation_failure() {
    let client_id = 88888;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create quote coin for ALICE
    scenario.next_tx(ALICE);
    let quote_coin = mint_for_testing<USDC>(QUOTE_AMOUNT, scenario.ctx());

    // Execute the quote-to-base swap with a minimum output that will fail
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        // Get the exact output from DeepBook using get_quantity_out_input_fee
        let (deepbook_base_out, _, _) = pool.get_quantity_out_input_fee(
            0, // base_quantity (0 for quote-to-base swap)
            QUOTE_AMOUNT, // quote_quantity
            &clock,
        );

        // Set minimum to slightly less than what DeepBook gives us
        // This ensures DeepBook passes but our validation fails after fees
        let impossible_min_base_out = deepbook_base_out - 1; // 1 nano SUI less than DeepBook output

        let (base_out, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin,
            impossible_min_base_out,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // This should never be reached - the function should abort above
        // But if it doesn't abort, we need to clean up the coins
        destroy(base_out);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 5: Zero input amount tests ===

#[test, expected_failure(abort_code = EInvalidQuantityIn)]
fun base_to_quote_zero_input() {
    let client_id = 11111;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create zero base coin for ALICE
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(0, scenario.ctx());

    // Execute the swap with zero input
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_remainder, quote_out) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin,
            0, // min_quote_out = 0 since we expect no output
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Verify results - should get zero output
        assert!(base_remainder.value() == 0); // No remainder since input was 0
        assert!(quote_out.value() == 0); // No output since input was 0

        // Cleanup
        destroy(base_remainder);
        destroy(quote_out);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EInvalidQuantityIn)]
fun quote_to_base_zero_input() {
    let client_id = 22222;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create zero quote coin for ALICE
    scenario.next_tx(ALICE);
    let quote_coin = mint_for_testing<USDC>(0, scenario.ctx());

    // Execute the swap with zero input
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin,
            0, // min_base_out = 0 since we expect no output
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Verify results - should get zero output
        assert!(base_out.value() == 0); // No output since input was 0
        assert!(quote_remainder.value() == 0); // No remainder since input was 0

        // Cleanup
        destroy(base_out);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 6: Loyalty level comparison test ===

#[test]
fun loyalty_level_comparison() {
    let client_id = 33333;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // === Phase 1: No loyalty level (0% discount) ===
    // Create base coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let base_coin_no_loyalty = mint_for_testing<SUI>(SCALE, scenario.ctx()); // 1 SUI
    let no_loyalty_output: u64;
    let bronze_output: u64;
    let gold_output: u64;

    // Execute swap with no loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_remainder, quote_out_no_loyalty) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin_no_loyalty,
            MIN_QUOTE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        no_loyalty_output = quote_out_no_loyalty.value();

        // Cleanup
        destroy(base_remainder);
        destroy(quote_out_no_loyalty);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    // === Phase 2: Grant Bronze loyalty level (10% discount) ===
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            1, // LEVEL_BRONZE
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create base coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let base_coin_bronze = mint_for_testing<SUI>(SCALE, scenario.ctx()); // 1 SUI

    // Execute swap with Bronze loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_remainder, quote_out_bronze) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin_bronze,
            MIN_QUOTE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        bronze_output = quote_out_bronze.value();

        // Verify Bronze output is higher than no loyalty (better discount)
        assert!(bronze_output > no_loyalty_output);

        // Cleanup
        destroy(base_remainder);
        destroy(quote_out_bronze);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    // === Phase 3: Revoke Bronze and grant Gold loyalty level (50% discount) ===
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Revoke Bronze level
        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        // Grant Gold level
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            3, // LEVEL_GOLD
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create base coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let base_coin_gold = mint_for_testing<SUI>(SCALE, scenario.ctx()); // 1 SUI

    // Execute swap with Gold loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_remainder, quote_out_gold) = swap_exact_base_for_quote_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            base_coin_gold,
            MIN_QUOTE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        gold_output = quote_out_gold.value();

        // Verify Gold output is higher than Bronze (better discount)
        assert!(gold_output > bronze_output);
        // Verify Gold output is higher than no loyalty (better discount)
        assert!(gold_output > no_loyalty_output);

        // Cleanup
        destroy(base_remainder);
        destroy(quote_out_gold);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test]
fun loyalty_level_comparison_quote_to_base() {
    let client_id = 44444;

    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // === Phase 1: No loyalty level (0% discount) ===
    // Create quote coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let quote_coin_no_loyalty = mint_for_testing<USDC>(SCALE, scenario.ctx()); // 1 USDC
    let no_loyalty_output: u64;
    let bronze_output: u64;
    let gold_output: u64;

    // Execute swap with no loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out_no_loyalty, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin_no_loyalty,
            MIN_BASE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        no_loyalty_output = base_out_no_loyalty.value();

        // Cleanup
        destroy(base_out_no_loyalty);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    // === Phase 2: Grant Bronze loyalty level (10% discount) ===
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            1, // LEVEL_BRONZE
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create quote coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let quote_coin_bronze = mint_for_testing<USDC>(SCALE, scenario.ctx()); // 1 USDC

    // Execute swap with Bronze loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out_bronze, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin_bronze,
            MIN_BASE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        bronze_output = base_out_bronze.value();

        // Verify Bronze output is higher than no loyalty (better discount)
        assert!(bronze_output > no_loyalty_output);

        // Cleanup
        destroy(base_out_bronze);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    // === Phase 3: Revoke Bronze and grant Gold loyalty level (50% discount) ===
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Revoke Bronze level
        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        // Grant Gold level
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            3, // LEVEL_GOLD
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Create quote coin for ALICE - use smaller amount to avoid liquidity impact
    scenario.next_tx(ALICE);
    let quote_coin_gold = mint_for_testing<USDC>(SCALE, scenario.ctx()); // 1 USDC

    // Execute swap with Gold loyalty
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out_gold, quote_remainder) = swap_exact_quote_for_base_input_fee(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            quote_coin_gold,
            MIN_BASE_OUT,
            client_id,
            &clock,
            scenario.ctx(),
        );

        // Store the output for comparison
        gold_output = base_out_gold.value();

        // Verify Gold output is higher than Bronze (better discount)
        assert!(gold_output > bronze_output);
        // Verify Gold output is higher than no loyalty (better discount)
        assert!(gold_output > no_loyalty_output);

        // Cleanup
        destroy(base_out_gold);
        destroy(quote_remainder);
        return_shared(treasury);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}
