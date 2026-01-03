#[test_only]
module deeptrade_core::create_market_order_tests;

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
use deeptrade_core::dt_math as math;
use deeptrade_core::dt_order::{Self as order, create_market_order};
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::get_sui_per_deep_from_oracle_tests::{
    new_deep_price_object,
    new_sui_price_object
};
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use deeptrade_core::treasury;
use pyth::price_info::PriceInfoObject;
use std::unit_test::assert_eq;
use sui::clock;
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
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
    ) = setup_test_environment();

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
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<clock::Clock>();

        // Create input coins for the market order
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
        let sui_coin = coin::mint_for_testing<SUI>(
            100 * constants::float_scaling(),
            scenario.ctx(),
        );

        let order_amount = math::mul(quantity, price);

        // Record initial balances
        let initial_balance_manager_base = balance_manager.balance<SUI>();
        let initial_balance_manager_quote = balance_manager.balance<USDC>();
        let initial_balance_manager_deep = balance_manager.balance<DEEP>();
        let initial_balance_manager_sui = balance_manager.balance<SUI>();
        let initial_wallet_base = base_coin.value();
        let initial_wallet_quote = quote_coin.value();
        let initial_wallet_deep = deep_coin.value();
        let initial_wallet_sui = sui_coin.value();

        // Execute market buy order
        let (order_info, base_coin, quote_coin, deep_coin, sui_coin) = create_market_order<
            SUI,
            USDC,
            DEEP,
            SUI,
        >(
            &mut treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &mut balance_manager,
            base_coin,
            quote_coin,
            deep_coin,
            sui_coin,
            order_amount, // order_amount (100 USDC)
            true, // is_bid (buy order)
            constants::self_matching_allowed(),
            2, // client_order_id
            50 * constants::float_scaling(), // estimated_deep_required
            10_000_000, // estimated_deep_required_slippage (1%)
            10 * constants::float_scaling(), // estimated_sui_fee
            10_000_000, // estimated_sui_fee_slippage (1%)
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
        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), true);
        assert!(fee_manager.get_protocol_unsettled_fee_balance<USDC>() > 0);

        // Verify coin consumption

        let final_balance_manager_base = balance_manager.balance<SUI>();
        let final_balance_manager_quote = balance_manager.balance<USDC>();
        let final_balance_manager_deep = balance_manager.balance<DEEP>();
        let final_balance_manager_sui = balance_manager.balance<SUI>();
        let final_wallet_base = base_coin.value();
        let final_wallet_quote = quote_coin.value();
        let final_wallet_deep = deep_coin.value();
        let final_wallet_sui = sui_coin.value();

        // For bid orders, fees and input coins should come from quote coins. Balance manager base balance
        // should increase due to order execution, while wallet base balance should remain unchanged.
        assert!(final_balance_manager_base > initial_balance_manager_base);
        assert!(final_balance_manager_quote < initial_balance_manager_quote);
        assert!(final_balance_manager_deep <= initial_balance_manager_deep);
        assert!(final_balance_manager_sui > initial_balance_manager_sui); // SUI is base coin
        assert_eq!(final_wallet_base, initial_wallet_base);
        assert!(final_wallet_quote <= initial_wallet_quote);
        assert!(final_wallet_deep <= initial_wallet_deep);
        assert_eq!(final_wallet_sui, initial_wallet_sui); // SUI is base coin

        // Clean up
        destroy(base_coin);
        destroy(quote_coin);
        destroy(deep_coin);
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(reference_pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Clean up price info objects
    destroy(deep_price);
    destroy(sui_price);

    end(scenario);
}

#[test, expected_failure(abort_code = order::ENotSupportedSelfMatchingOption)]
fun unsupported_self_matching_option() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        reference_pool_id,
        deep_price,
        sui_price,
    ) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Step 2: Try to execute market buy order with unsupported self-matching option
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<clock::Clock>();

        // Create input coins for the market order
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
        let sui_coin = coin::mint_for_testing<SUI>(
            100 * constants::float_scaling(),
            scenario.ctx(),
        );

        let order_amount = math::mul(quantity, price);

        // This should fail with ENotSupportedSelfMatchingOption
        let (_order_info, base_coin, quote_coin, deep_coin, sui_coin) = create_market_order<
            SUI,
            USDC,
            DEEP,
            SUI,
        >(
            &mut treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &mut balance_manager,
            base_coin,
            quote_coin,
            deep_coin,
            sui_coin,
            order_amount, // order_amount (100 USDC)
            true, // is_bid (buy order)
            constants::cancel_taker(), // ❌ Unsupported self-matching option
            2, // client_order_id
            50 * constants::float_scaling(), // estimated_deep_required
            10_000_000, // estimated_deep_required_slippage (1%)
            10 * constants::float_scaling(), // estimated_sui_fee
            10_000_000, // estimated_sui_fee_slippage (1%)
            &clock,
            scenario.ctx(),
        );

        // Clean up (this should not be reached due to the expected failure)
        destroy(base_coin);
        destroy(quote_coin);
        destroy(deep_coin);
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(loyalty_program);
        return_shared(pool);
        return_shared(reference_pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Clean up price info objects (this should not be reached due to the expected failure)
    destroy(deep_price);
    destroy(sui_price);

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with treasury, deepbook infrastructure, and fee components.
/// Returns (scenario, pool_id, balance_manager_id, fee_manager_id, reference_pool_id, deep_price, sui_price) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): (
    Scenario,
    ID,
    ID,
    ID,
    ID,
    PriceInfoObject,
    PriceInfoObject,
) {
    let mut scenario = begin(OWNER);

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

    // Add funds to balance manager for placing limit order
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
    )
}
