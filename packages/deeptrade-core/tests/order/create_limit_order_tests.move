#[test_only]
module deeptrade_core::create_limit_order_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::USDC;
use deepbook::constants;
use deepbook::pool::Pool;
use deeptrade_core::create_market_order_tests::setup_test_environment;
use deeptrade_core::fee::TradingFeeConfig;
use deeptrade_core::fee_manager::FeeManager;
use deeptrade_core::loyalty::LoyaltyProgram;
use deeptrade_core::order::{Self, create_limit_order};
use deeptrade_core::treasury;
use std::unit_test::assert_eq;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
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

    // Execute limit buy order
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

        // Create input coins for the limit order
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

        // Execute limit buy order
        let (order_info, base_coin, quote_coin, deep_coin, sui_coin) = create_limit_order<
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
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            constants::max_u64(), // expire_timestamp
            constants::no_restriction(), // order_type (GTC)
            constants::self_matching_allowed(), // self_matching_option
            1, // client_order_id
            50 * constants::float_scaling(), // estimated_deep_required
            10_000_000, // estimated_deep_required_slippage (1%)
            10 * constants::float_scaling(), // estimated_sui_fee
            10_000_000, // estimated_sui_fee_slippage (1%)
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

#[test, expected_failure(abort_code = order::ENotSupportedExpireTimestamp)]
fun not_supported_expire_timestamp() {
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

    // Try to execute limit buy order with unsupported expire timestamp
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

        // Create input coins for the limit order
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

        // This should fail with ENotSupportedExpireTimestamp
        let (_order_info, base_coin, quote_coin, deep_coin, sui_coin) = create_limit_order<
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
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            1234567890, // ❌ Invalid expire_timestamp (not max_u64())
            constants::no_restriction(), // order_type (GTC)
            constants::self_matching_allowed(), // self_matching_option
            1, // client_order_id
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

#[test, expected_failure(abort_code = order::ENotSupportedSelfMatchingOption)]
fun not_supported_self_matching_option() {
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

    // Try to execute limit buy order with unsupported self-matching option
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

        // Create input coins for the limit order
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

        // This should fail with ENotSupportedSelfMatchingOption
        let (_order_info, base_coin, quote_coin, deep_coin, sui_coin) = create_limit_order<
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
            price, // price (2.0)
            quantity, // quantity (50 SUI)
            true, // is_bid (buy order)
            constants::max_u64(), // expire_timestamp
            constants::no_restriction(), // order_type (GTC)
            constants::cancel_taker(), // ❌ Unsupported self-matching option
            1, // client_order_id
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
