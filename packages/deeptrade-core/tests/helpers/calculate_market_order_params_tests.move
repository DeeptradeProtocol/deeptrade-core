#[test_only]
module deeptrade_core::calculate_market_order_params_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees,
    setup_reference_pool,
    place_limit_order,
    add_deep_price_point,
    set_time
};
use deeptrade_core::fee;
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::get_sui_per_deep_from_oracle_tests::{
    new_deep_price_object,
    new_sui_price_object
};
use deeptrade_core::helper;
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use deeptrade_core::multisig_config::MultisigConfig;
use deeptrade_core::treasury;
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use pyth::price_info::{Self, PriceInfoObject};
use std::unit_test::assert_eq;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;
const BRONZE_DISCOUNT: u64 = 50_000_000; // 5%
const SILVER_DISCOUNT: u64 = 100_000_000; // 10%
const GOLD_DISCOUNT: u64 = 150_000_000; // 15%

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

/// Test that bid orders correctly floor base quantity to lot size
#[test]
fun bid_lot_size_flooring() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        _fee_manager_id,
        _reference_pool_id,
        deep_price,
        sui_price,
        _loyalty_program_id,
    ) = setup_test_environment();

    // Place limit sell orders to create liquidity in the order book
    let sell_quantity = 100 * constants::float_scaling();
    let sell_price = 2 * constants::float_scaling();

    let order_info = place_limit_order<SUI, USDC>(
        ALICE,
        pool_id,
        balance_manager_id,
        1, // client_order_id
        constants::no_restriction(),
        constants::self_matching_allowed(),
        sell_price, // price (2.0)
        sell_quantity, // quantity (100 SUI)
        false, // is_bid (sell order)
        true, // pay_with_deep
        constants::max_u64(), // expire_timestamp
        &mut scenario,
    );

    // Test the calculate_market_order_params function
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<clock::Clock>();

        // Get pool parameters to understand lot size
        let (_, lot_size, _) = pool.pool_book_params();

        // Use a reasonable quote amount for testing
        let quote_amount = 50000; // 50000 (small units)
        let (base_out_raw, _, deep_req) = pool.get_quantity_out(0, quote_amount, &clock);

        // Calculate expected floored base quantity
        let expected_base_quantity = base_out_raw - base_out_raw % lot_size;

        // Test the function
        let (base_quantity, deep_required) = helper::calculate_market_order_params<SUI, USDC>(
            &pool,
            quote_amount,
            true, // is_bid
            &clock,
        );

        // Verify the base quantity is floored to lot size
        assert_eq!(base_quantity, expected_base_quantity);
        assert_eq!(base_quantity % lot_size, 0);
        assert_eq!(deep_required, deep_req);

        // Verify the flooring behavior: either base_quantity < base_out_raw (if not aligned)
        // or base_quantity == base_out_raw (if already aligned)
        assert!(base_quantity <= base_out_raw);
        if (base_out_raw % lot_size != 0) {
            assert!(base_quantity < base_out_raw);
        } else {
            assert_eq!(base_quantity, base_out_raw);
        };

        return_shared(pool);
        return_shared(clock);
    };

    // Clean up
    destroy(order_info);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    end(scenario);
}

/// Test that ask orders correctly use the provided base quantity and calculate DEEP requirements
#[test]
fun ask_base_quantity_direct() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        _fee_manager_id,
        _reference_pool_id,
        deep_price,
        sui_price,
        _loyalty_program_id,
    ) = setup_test_environment();

    // Place limit buy orders to create liquidity in the order book
    let buy_quantity = 100 * constants::float_scaling();
    let buy_price = 2 * constants::float_scaling();

    let order_info = place_limit_order<SUI, USDC>(
        ALICE,
        pool_id,
        balance_manager_id,
        1, // client_order_id
        constants::no_restriction(),
        constants::self_matching_allowed(),
        buy_price, // price (2.0)
        buy_quantity, // quantity (100 SUI)
        true, // is_bid (buy order)
        true, // pay_with_deep
        constants::max_u64(), // expire_timestamp
        &mut scenario,
    );

    // Test the calculate_market_order_params function for ask orders
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<clock::Clock>();

        // Get pool parameters (lot_size not used in ask test)
        let (_, _, _) = pool.pool_book_params();

        // Use a base amount for testing
        let base_amount = 1234; // 1234 (not aligned with lot size 1000)

        // Get expected DEEP requirement from get_quantity_out
        let (_, _, expected_deep_req) = pool.get_quantity_out(base_amount, 0, &clock);

        // Test the function
        let (base_quantity, deep_required) = helper::calculate_market_order_params<SUI, USDC>(
            &pool,
            base_amount,
            false, // is_bid (ask order)
            &clock,
        );

        // For ask orders, the base quantity should be the provided amount (not floored)
        assert_eq!(base_quantity, base_amount);
        assert_eq!(deep_required, expected_deep_req);

        // Verify the base quantity is not floored (unlike bids)
        // For asks, the function should use the order_amount directly
        assert_eq!(base_quantity, base_amount);

        return_shared(pool);
        return_shared(clock);
    };

    // Clean up
    destroy(order_info);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    end(scenario);
}
