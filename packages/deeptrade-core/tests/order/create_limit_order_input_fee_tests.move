#[test_only]
module deeptrade_core::create_limit_order_input_fee_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::USDC;
use deepbook::constants;
use deepbook::pool::Pool;
use deeptrade_core::create_market_order_input_fee_tests::setup_test_environment;
use deeptrade_core::dt_order::{Self as order, create_limit_order_input_fee};
use deeptrade_core::fee::TradingFeeConfig;
use deeptrade_core::fee_manager::FeeManager;
use deeptrade_core::loyalty::LoyaltyProgram;
use deeptrade_core::treasury;
use std::unit_test::assert_eq;
use sui::clock::Clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const ALICE: address = @0xAAAA;

#[test]
fun success() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Execute limit buy order
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Create input coins for the limit order
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );

        // Record initial balances
        let initial_balance_manager_base = balance_manager.balance<SUI>();
        let initial_balance_manager_quote = balance_manager.balance<USDC>();
        let initial_wallet_base = base_coin.value();
        let initial_wallet_quote = quote_coin.value();

        // Execute limit buy order
        let (order_info, base_coin, quote_coin) = create_limit_order_input_fee<SUI, USDC>(
            &treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &mut balance_manager,
            base_coin,
            quote_coin,
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            constants::max_u64(), // expire_timestamp
            constants::no_restriction(), // order_type (GTC)
            constants::self_matching_allowed(), // self_matching_option
            1, // client_order_id
            &clock,
            scenario.ctx(),
        );

        // Verify the limit order was created successfully
        assert_eq!(order_info.original_quantity(), quantity);
        assert_eq!(order_info.price(), price);
        assert_eq!(order_info.is_bid(), true);

        // Check that the order is in open orders
        let open_orders = pool.account_open_orders(&balance_manager);
        assert_eq!(open_orders.size(), 1);

        // Check that user unsettled fees are added to the fee manager
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert!(
            fee_manager.get_user_unsettled_fee_balance<USDC>(
            order_info.pool_id(),
            order_info.balance_manager_id(),
            order_info.order_id(),
        ) > 0,
        );

        // Verify coin consumption
        let final_balance_manager_base = balance_manager.balance<SUI>();
        let final_balance_manager_quote = balance_manager.balance<USDC>();
        let final_wallet_base = base_coin.value();
        let final_wallet_quote = quote_coin.value();

        // For bid orders, fees should come from quote coins, base coins should remain unchanged
        assert_eq!(final_balance_manager_base, initial_balance_manager_base);
        assert!(final_balance_manager_quote <= initial_balance_manager_quote);
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

#[test, expected_failure(abort_code = order::ENotSupportedExpireTimestamp)]
fun test_not_supported_expire_timestamp() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Try to execute limit buy order with unsupported expire timestamp
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Create input coins for the limit order
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );

        // This should fail with ENotSupportedExpireTimestamp
        let (_order_info, base_coin, quote_coin) = create_limit_order_input_fee<SUI, USDC>(
            &treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &mut balance_manager,
            base_coin,
            quote_coin,
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            1234567890, // ❌ Invalid expire_timestamp (not max_u64())
            constants::no_restriction(), // order_type (GTC)
            constants::self_matching_allowed(), // self_matching_option
            1, // client_order_id
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

#[test, expected_failure(abort_code = order::ENotSupportedSelfMatchingOption)]
fun test_not_supported_self_matching_option() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    let quantity = 50 * constants::float_scaling();
    let price = 2 * constants::float_scaling();

    // Try to execute limit buy order with unsupported self-matching option
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Create input coins for the limit order
        let base_coin = coin::mint_for_testing<SUI>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );
        let quote_coin = coin::mint_for_testing<USDC>(
            1000 * constants::float_scaling(),
            scenario.ctx(),
        );

        // This should fail with ENotSupportedSelfMatchingOption
        let (_order_info, base_coin, quote_coin) = create_limit_order_input_fee<SUI, USDC>(
            &treasury,
            &mut fee_manager,
            &trading_fee_config,
            &loyalty_program,
            &mut pool,
            &mut balance_manager,
            base_coin,
            quote_coin,
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            constants::max_u64(), // expire_timestamp
            constants::no_restriction(), // order_type (GTC)
            constants::cancel_taker(), // ❌ Unsupported self-matching option
            1, // client_order_id
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
