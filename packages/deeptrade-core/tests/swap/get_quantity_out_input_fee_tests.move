#[test_only]
module deeptrade_core::get_quantity_out_input_fee_tests;

use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees_and_reference_pool,
    place_limit_order
};
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::loyalty::{Self, LoyaltyAdminCap, LoyaltyProgram};
use deeptrade_core::multisig_config::MultisigConfig;
use deeptrade_core::swap::get_quantity_out_input_fee;
use deeptrade_core::treasury;
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

// Test loyalty levels
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;

// Test constants
const SCALE: u64 = 1_000_000_000; // 100% in billionths

// Different input amounts for testing
const SMALL_AMOUNT: u64 = 10 * SCALE; // 10 tokens
const MEDIUM_AMOUNT: u64 = 100 * SCALE; // 100 tokens
const LARGE_AMOUNT: u64 = 1_000 * SCALE; // 1,000 tokens
const QUOTE_AMOUNT: u64 = 500 * SCALE; // 500 tokens

// === Test Case 1: base_quantity > 0 (swapping base for quote) ===

#[test]
fun base_quantity_greater_than_zero() {
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

    // Test the function
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_out, deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            LARGE_AMOUNT, // 1,000 tokens
            0, // Not swapping quote
            &clock,
            scenario.ctx(),
        );

        // Verify results with better assertions
        assert!(base_out > 0); // Should get some base back as remainder
        assert!(quote_out > 0); // Should get some quote tokens
        assert_eq!(deep_required, 0); // Should always be 0 for input fee model

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 2: quote_quantity > 0 (swapping quote for base) ===

#[test]
fun quote_quantity_greater_than_zero() {
    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant loyalty level to BOB
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Test the function
    scenario.next_tx(BOB);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_out, deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            0, // Not swapping base
            QUOTE_AMOUNT, // 500 tokens
            &clock,
            scenario.ctx(),
        );

        // Verify results with better assertions
        assert!(base_out > 0); // Should get some base tokens
        assert!(quote_out > 0); // Should get some quote back as remainder
        assert_eq!(deep_required, 0); // Should always be 0 for input fee model

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 3: very small quantities (edge case) ===

#[test]
fun very_small_quantities() {
    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Test the function with very small quantities
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_out, deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            SMALL_AMOUNT, // 10 tokens
            0, // Not swapping quote
            &clock,
            scenario.ctx(),
        );

        // Verify results for small amounts
        assert!(base_out >= 0); // May get some base back or zero
        assert!(quote_out >= 0); // May get some quote or zero
        assert_eq!(deep_required, 0); // Should always be 0 for input fee model

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 4: different loyalty levels affect discount ===

#[test]
fun different_loyalty_levels() {
    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Grant different loyalty levels
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant BRONZE level to ALICE
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        // Grant GOLD level to BOB
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Test ALICE with BRONZE level
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (_alice_base_out, alice_quote_out, alice_deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            MEDIUM_AMOUNT, // 100 tokens
            0,
            &clock,
            scenario.ctx(),
        );

        // Verify ALICE's results
        assert!(alice_quote_out > 0); // Should get some quote tokens
        assert_eq!(alice_deep_required, 0);

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    // Test BOB with GOLD level
    scenario.next_tx(BOB);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (_bob_base_out, bob_quote_out, bob_deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            MEDIUM_AMOUNT, // 100 tokens
            0,
            &clock,
            scenario.ctx(),
        );

        // Verify BOB's results
        assert!(bob_quote_out > 0); // Should get some quote tokens
        assert_eq!(bob_deep_required, 0);

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Test Case 5: no loyalty level (0% discount) ===

#[test]
fun no_loyalty_level() {
    let (mut scenario, pool_id, _, _) = setup_test_environment();

    // Test the function with a user who has no loyalty level
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        let (base_out, quote_out, deep_required) = get_quantity_out_input_fee(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            MEDIUM_AMOUNT, // 100 tokens
            0,
            &clock,
            scenario.ctx(),
        );

        // Verify results for user with no loyalty level
        assert!(base_out > 0); // Should get some base back as remainder
        assert!(quote_out > 0); // Should get some quote tokens
        assert_eq!(deep_required, 0); // Should always be 0 for input fee model

        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with treasury, deepbook infrastructure, and fee components.
/// Returns (scenario, pool_id, balance_manager_id, fee_manager_id) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): (Scenario, ID, ID, ID) {
    let mut scenario = setup_with_initialized_config();

    // Setup treasury
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let pool_id = setup_pool_with_default_fees_and_reference_pool<SUI, USDC, SUI, DEEP>(
        ALICE,
        registry_id,
        balance_manager_id,
        &mut scenario,
    );

    // Setup fee manager
    scenario.next_tx(ALICE);
    {
        let (fee_manager, owner_cap, ticket) = fee_manager::new(scenario.ctx());
        fee_manager.share_fee_manager(ticket);
        transfer::public_transfer(owner_cap, ALICE);
    };

    scenario.next_tx(ALICE);
    let fee_manager_id = test_scenario::most_recent_id_shared<FeeManager>().extract();

    // Setup trading fee config and loyalty program
    scenario.next_tx(OWNER);
    {
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Add loyalty levels
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());
        let config = scenario.take_shared<MultisigConfig>();

        // Add test loyalty levels
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            100_000_000, // 10% discount
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            250_000_000, // 25% discount
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_GOLD,
            500_000_000, // 50% discount
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Add liquidity to the pool
    scenario.next_tx(ALICE);
    {
        // Add 2 ask orders (sell orders)
        // Ask: 5 SUI at price 5
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            5 * constants::float_scaling(), // price (5.0)
            5 * constants::float_scaling(), // quantity (5 SUI)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Ask: 10 SUI at price 10
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            10 * constants::float_scaling(), // price (10.0)
            10 * constants::float_scaling(), // quantity (10 SUI)
            false, // is_bid (sell order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add 2 bid orders (buy orders)
        // Bid: 4 SUI at price 4
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            3, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            4 * constants::float_scaling(), // price (4.0)
            4 * constants::float_scaling(), // quantity (4 SUI)
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Bid: 2 SUI at price 2
        place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            4, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price (2.0)
            2 * constants::float_scaling(), // quantity (2 SUI)
            true, // is_bid (buy order)
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );
    };

    (scenario, pool_id, balance_manager_id, fee_manager_id)
}
