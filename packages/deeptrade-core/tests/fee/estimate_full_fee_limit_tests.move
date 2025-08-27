#[test_only]
module deeptrade_core::estimate_full_fee_limit_tests;

use deepbook::balance_manager_tests::USDC;
use deepbook::constants;
use deepbook::pool::Pool;
use deeptrade_core::estimate_full_fee_market_tests::setup_test_environment;
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use multisig::multisig_test_utils::{
    get_test_multisig_address,
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold
};
use pyth::price_info;
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const ALICE: address = @0xAAAA;

// Test loyalty levels
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;

// Test constants
const DEEP_MULTIPLIER: u64 = 1_000_000; // DEEP has 6 decimals
const ORDER_QUANTITY: u64 = 100; // 100 base tokens (will be scaled in test)
const ORDER_PRICE: u64 = 2; // 2 quote tokens per base token (will be scaled in test)

#[test]
fun mixed_deep_coverage_scenario() {
    let (
        mut scenario,
        pool_id,
        _balance_manager_id,
        _fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
        loyalty_program_id,
    ) = setup_test_environment();

    // Grant user loyalty level (Silver = 25% discount)
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Test the estimate_full_fee_limit function
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let clock = scenario.take_shared<clock::Clock>();

        // User has 1 DEEP in balance manager + 1 DEEP in wallet = 2 DEEP total
        let deep_in_balance_manager = DEEP_MULTIPLIER; // 1 DEEP
        let deep_in_wallet = DEEP_MULTIPLIER; // 1 DEEP

        let (
            _deep_reserves_coverage_fee,
            protocol_fee,
            deep_required,
            discount_rate,
        ) = fee::estimate_full_fee_limit<SUI, USDC, DEEP, SUI>(
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &trading_fee_config,
            &loyalty_program,
            deep_in_balance_manager,
            deep_in_wallet,
            ORDER_QUANTITY * constants::float_scaling(),
            ORDER_PRICE * constants::float_scaling(),
            true, // is_bid (buy order)
            &clock,
            scenario.ctx(),
        );

        // Expected calculations:
        // DEEP/USD price = 3.00 USD per DEEP, SUI/USD price = 1.00 USD per SUI
        // This gives SUI/DEEP price ≈ 0.333 (1/3) for fee calculations
        // deep_from_reserves = deep_required - 1 - 1 = deep_required - 2 DEEP
        // deep_reserves_coverage_fee = deep_from_reserves × SUI/DEEP price (converted to appropriate scale)

        // Verify the function returns reasonable values
        assert!(deep_required > 0);
        assert!(discount_rate >= 0);
        assert!(protocol_fee >= 0);

        // Test specific scenario: User has 2 DEEP total, needs more from reserves
        // With Silver loyalty level (25% discount) and partial coverage discount
        // The total discount should be between 0% and 50% (25% + partial coverage)
        assert!(discount_rate <= 500_000_000); // Max 50% for this scenario

        // Verify that the function completed successfully and returned reasonable values
        // Note: The exact values depend on the limit order calculation and DEEP requirements

        return_shared(pool);
        return_shared(reference_pool);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(clock);
    };

    // Clean up price info objects
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);

    end(scenario);
}

#[test]
fun sell_order_scenario() {
    let (
        mut scenario,
        pool_id,
        _balance_manager_id,
        _fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
        loyalty_program_id,
    ) = setup_test_environment();

    // Grant user loyalty level (Gold = 50% discount)
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Test the estimate_full_fee_limit function for a sell order
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let clock = scenario.take_shared<clock::Clock>();

        // User has 5 DEEP in balance manager + 0 DEEP in wallet = 5 DEEP total
        let deep_in_balance_manager = 5 * DEEP_MULTIPLIER; // 5 DEEP
        let deep_in_wallet = 0; // 0 DEEP

        let (
            _deep_reserves_coverage_fee,
            protocol_fee,
            deep_required,
            discount_rate,
        ) = fee::estimate_full_fee_limit<SUI, USDC, DEEP, SUI>(
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &trading_fee_config,
            &loyalty_program,
            deep_in_balance_manager,
            deep_in_wallet,
            ORDER_QUANTITY * constants::float_scaling(),
            ORDER_PRICE * constants::float_scaling(),
            false, // is_bid (sell order)
            &clock,
            scenario.ctx(),
        );

        // Verify the function returns reasonable values
        assert!(deep_required > 0);
        assert!(discount_rate >= 0);
        assert!(protocol_fee >= 0);

        // Test specific scenario: User has 5 DEEP total, should have good coverage
        // With Gold loyalty level (50% discount) and good coverage discount
        // The total discount should be between 0% and 75% (50% + coverage discount)
        assert!(discount_rate <= 750_000_000); // Max 75% for this scenario

        return_shared(pool);
        return_shared(reference_pool);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(clock);
    };

    // Clean up price info objects
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);

    end(scenario);
}
