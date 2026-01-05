#[test_only]
module deeptrade_core::create_market_order_input_fee_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees_and_reference_pool,
    place_limit_order
};
use deeptrade_core::dt_math as math;
use deeptrade_core::dt_order::{Self as order, create_market_order_input_fee};
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use deeptrade_core::treasury;
use std::unit_test::assert_eq;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario, begin, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

#[test]
fun success() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Step 1: Place a limit sell order to create liquidity
    let order_info = place_limit_order<SUI, USDC>(
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
    let limit_order_id = order_info.order_id();

    // Step 2: Execute market buy order to match against the limit sell order
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Create input coins for the market order
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );

        let order_amount = math::mul(quantity, price);

        // Record initial balances
        let initial_balance_manager_base = balance_manager.balance<SUI>();
        let initial_balance_manager_quote = balance_manager.balance<USDC>();
        let initial_wallet_base = base_coin.value();
        let initial_wallet_quote = quote_coin.value();

        // Execute market buy order
        let (order_info, base_coin, quote_coin) = create_market_order_input_fee<SUI, USDC>(
            &treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &mut balance_manager,
            base_coin,
            quote_coin,
            order_amount, // order_amount (100 USDC)
            true, // is_bid (buy order)
            constants::self_matching_allowed(),
            2, // client_order_id
            &clock,
            scenario.ctx(),
        );

        // Verify the market order was executed
        assert_eq!(order_info.executed_quantity(), quantity);

        // Check open orders status
        let open_orders = pool.account_open_orders(&balance_manager);
        let limit_order_still_exists = open_orders.contains(&limit_order_id);

        // Verify the market order executed
        assert_eq!(limit_order_still_exists, false);
        assert_eq!(open_orders.size(), 0);

        // Verify coin consumption
        let final_balance_manager_base = balance_manager.balance<SUI>();
        let final_balance_manager_quote = balance_manager.balance<USDC>();
        let final_wallet_base = base_coin.value();
        let final_wallet_quote = quote_coin.value();

        // For bid orders, fees and input coins should come from quote coins. Balance manager base balance
        // should increase due to order execution, while wallet base balance should remain unchanged.
        assert!(final_balance_manager_base > initial_balance_manager_base);
        assert!(final_balance_manager_quote < initial_balance_manager_quote);
        assert_eq!(final_wallet_base, initial_wallet_base);
        assert!(final_wallet_quote <= initial_wallet_quote);

        // Clean up
        destroy(base_coin);
        destroy(quote_coin);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = order::ENotSupportedSelfMatchingOption)]
fun test_not_supported_self_matching_option() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Try to execute market buy order with unsupported self-matching option
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Create input coins for the market order
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );

        let order_amount = math::mul(quantity, price);

        // This should fail with ENotSupportedSelfMatchingOption
        let (_order_info, base_coin, quote_coin) = create_market_order_input_fee<SUI, USDC>(
            &treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &mut balance_manager,
            base_coin,
            quote_coin,
            order_amount, // order_amount (100 USDC)
            true, // is_bid (buy order)
            constants::cancel_taker(), // ❌ Unsupported self-matching option
            2, // client_order_id
            &clock,
            scenario.ctx(),
        );

        // Clean up (this should not be reached due to the expected failure)
        destroy(base_coin);
        destroy(quote_coin);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with treasury, deepbook infrastructure, and fee components.
/// Returns (scenario, pool_id, balance_manager_id, fee_manager_id) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): (Scenario, ID, ID, ID) {
    let mut scenario = begin(OWNER);

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

    (scenario, pool_id, balance_manager_id, fee_manager_id)
}
