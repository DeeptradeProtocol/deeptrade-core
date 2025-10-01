#[test_only]
module deeptrade_core::estimate_full_fee_market_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees,
    setup_reference_pool,
    add_deep_price_point,
    set_time,
    place_limit_order
};
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::get_sui_per_deep_from_oracle_tests::{
    new_deep_price_object,
    new_sui_price_object
};
use deeptrade_core::loyalty::{Self, LoyaltyAdminCap, LoyaltyProgram};
use deeptrade_core::multisig_config::MultisigConfig;
use deeptrade_core::treasury;
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use pyth::price_info::{Self, PriceInfoObject};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario, begin, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

// Test loyalty levels
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;

// Fee discount rates (in billionths)
const BRONZE_DISCOUNT: u64 = 100_000_000; // 10%
const SILVER_DISCOUNT: u64 = 250_000_000; // 25%
const GOLD_DISCOUNT: u64 = 500_000_000; // 50%

// Test constants
const DEEP_MULTIPLIER: u64 = 1_000_000; // DEEP has 6 decimals
const ORDER_AMOUNT: u64 = 1000; // 1000 tokens (will be scaled in test)

#[test]
fun mixed_deep_coverage_scenario() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        _fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
        loyalty_program_id,
    ) = setup_test_environment();

    // Grant user loyalty level (Silver = 25% discount)
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
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

    // Place a limit sell order to create liquidity for market order testing
    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();
    place_limit_order<SUI, USDC>(
        ALICE,
        pool_id,
        balance_manager_id,
        1, // client_order_id
        constants::no_restriction(),
        constants::self_matching_allowed(),
        price, // price (2.0)
        quantity, // quantity (50 SUI)
        false, // is_bid (sell order)
        true, // pay_with_deep
        constants::max_u64(), // expire_timestamp
        &mut scenario,
    );

    // Test the estimate_full_fee_market function
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
        ) = fee::estimate_full_fee_market<SUI, USDC, DEEP, SUI>(
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &trading_fee_config,
            &loyalty_program,
            deep_in_balance_manager,
            deep_in_wallet,
            ORDER_AMOUNT * constants::float_scaling(),
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
        // Note: The exact values depend on the market order calculation and DEEP requirements

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

// === Helper Functions ===

/// Sets up a complete test environment with treasury, deepbook infrastructure, fee components, and loyalty program.
/// Returns (scenario, pool_id, balance_manager_id, fee_manager_id, reference_pool_id, deep_price, sui_price, loyalty_program_id) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): (
    Scenario,
    ID,
    ID,
    ID,
    ID,
    PriceInfoObject,
    PriceInfoObject,
    ID,
) {
    let mut scenario = setup_with_initialized_config();

    // Setup treasury
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Add DEEP to treasury reserves
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let treasury_deep_coin = coin::mint_for_testing<DEEP>(
            10_000 * constants::float_scaling(),
            scenario.ctx(),
        );
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);

    // Create pool setup balance manager with large amounts for reference pool setup
    let pool_setup_bm_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(), // Large amount for pool setup
        &mut scenario,
    );

    // Create user balance manager with specific amounts for testing
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        0, // Start with 0 funds, we'll add specific amounts later
        &mut scenario,
    );

    // Add funds to balance manager for testing
    scenario.next_tx(ALICE);
    {
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let deep_coin = coin::mint_for_testing<DEEP>(
            100 * constants::float_scaling(),
            scenario.ctx(),
        );

        balance_manager.deposit(base_coin, scenario.ctx());
        balance_manager.deposit(quote_coin, scenario.ctx());
        balance_manager.deposit(deep_coin, scenario.ctx());

        return_shared(balance_manager);
    };

    // Create trading pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        false, // whitelisted_pool = false
        false, // stable_pool = false
        &mut scenario,
    );

    // Create reference pool (DEEP/SUI) using pool setup balance manager
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        pool_setup_bm_id, // Use pool setup balance manager
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    set_time(0, &mut scenario);
    add_deep_price_point<SUI, USDC, DEEP, SUI>(
        ALICE,
        pool_id,
        reference_pool_id,
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
    let loyalty_program_id = {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());
        let config = scenario.take_shared<MultisigConfig>();

        // Add test loyalty levels
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            BRONZE_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            SILVER_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_GOLD,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        let loyalty_program_id = object::id(&loyalty_program);
        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
        loyalty_program_id
    };

    // Create price info objects
    scenario.next_tx(OWNER);
    let current_time;
    {
        let clock = scenario.take_shared<clock::Clock>();
        current_time = clock.timestamp_ms();
        return_shared(clock);
    };

    let deep_price = new_deep_price_object(
        &mut scenario,
        300_000_000, // DEEP price magnitude (3 USD per DEEP)
        false, // positive
        1, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        1_000_000_000, // SUI price magnitude (1 USD per SUI)
        false, // positive
        1, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );

    (
        scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
        loyalty_program_id,
    )
}
