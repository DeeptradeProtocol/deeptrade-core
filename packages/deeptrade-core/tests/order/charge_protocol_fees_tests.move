#[test_only]
module deeptrade_core::charge_protocol_fees_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{create_acct_and_share_with_funds, USDC};
use deepbook::constants;
use deepbook::order_info::{Self, OrderInfo};
use deepbook::pool::Pool;
use deepbook::pool_tests::{setup_test, setup_pool_with_default_fees};
use deeptrade_core::dt_order::charge_protocol_fees;
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::fee_manager::FeeManager;
use deeptrade_core::helper::calculate_order_taker_maker_ratio;
use deeptrade_core::treasury;
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

// Test constants
const ORDER_AMOUNT: u64 = 1_000_000; // 1M units
const DISCOUNT_RATE: u64 = 150_000_000; // 15% discount

#[test]
fun deep_fee_type_bid() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Create partially executed bid order (both taker and maker fees apply)
    let order_info = create_partially_executed_bid_order(
        ORDER_AMOUNT,
        600_000,
        pool_id,
        balance_manager_id,
    ); // 60% executed (40% maker)

    // Step 2: Calculate expected fees using default deep fee type rates
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    // Step 3: Setup wallet coins with sufficient funds
    scenario.next_tx(ALICE);
    let mut base_coin = mint_for_testing<SUI>(0, scenario.ctx()); // No need in base coins for bid order
    let mut quote_coin = mint_for_testing<USDC>(0, scenario.ctx()); // No coins in user's wallet

    // Step 4: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let (taker_fee_rate, maker_fee_rate) = trading_fee_config
            .get_pool_fee_config(&pool)
            .deep_fee_type_rates();

        let (total_fee, taker_fee, maker_fee) = fee::calculate_protocol_fees(
            taker_ratio,
            maker_ratio,
            taker_fee_rate,
            maker_fee_rate,
            ORDER_AMOUNT,
            DISCOUNT_RATE,
        );

        // Record initial balances
        let initial_balance_manager_quote = balance_manager.balance<USDC>();

        // Verify no protocol unsettled fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), false);

        // Verify no user unsettled fee exists initially
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Charge protocol fees with deep fee type
        charge_protocol_fees(
            &mut fee_manager,
            &trading_fee_config,
            &pool,
            &mut balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &order_info,
            ORDER_AMOUNT,
            DISCOUNT_RATE,
            true, // deep_fee_type = true
            scenario.ctx(),
        );

        // Step 5: Verify results

        // Verify taker fees are added to protocol unsettled fees
        let final_fee_manager_balance = fee_manager.get_protocol_unsettled_fee_balance<USDC>();
        assert_eq!(final_fee_manager_balance, taker_fee);

        // Verify maker fees are added to user unsettled fees
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<USDC>(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            maker_fee,
        );

        // Verify balance manager quote balance decreased by the fee amount
        let final_balance_manager_quote = balance_manager.balance<USDC>();
        assert_eq!(final_balance_manager_quote, initial_balance_manager_quote - total_fee);

        // Verify calculated fees are correct
        // Using default deep fee type rates: taker = 600_000 (0.06%), maker = 300_000 (0.03%)
        // 60% executed: taker_fee = 1_000_000 * 0.6 * 0.0006 = 360
        // 40% maker: maker_fee = 1_000_000 * 0.4 * 0.0003 = 120
        // 15% discount: total_fee = 480 * 0.85 = 408
        assert_eq!(taker_fee, 306); // 60% * 0.06% * 1_000_000 * 0.85 = 306
        assert_eq!(maker_fee, 102); // 40% * 0.03% * 1_000_000 * 0.85 = 102
        assert_eq!(total_fee, 408); // (360 + 120) * 0.85 = 408

        destroy(base_coin);
        destroy(quote_coin);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(pool);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun input_coin_fee_type_ask() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Create partially executed ask order (both taker and maker fees apply)
    let order_info = create_partially_executed_ask_order(
        ORDER_AMOUNT,
        200_000,
        pool_id,
        balance_manager_id,
    ); // 20% executed (80% maker)

    // Step 2: Calculate expected fees using input coin fee type rates
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    // Step 3: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        // Calculate protocol fees
        let (taker_fee_rate, maker_fee_rate) = trading_fee_config
            .get_pool_fee_config(&pool)
            .input_coin_fee_type_rates();

        let (total_fee, taker_fee, maker_fee) = fee::calculate_protocol_fees(
            taker_ratio,
            maker_ratio,
            taker_fee_rate,
            maker_fee_rate,
            ORDER_AMOUNT,
            DISCOUNT_RATE,
        );

        // Mint coins for fees
        let mut base_coin = mint_for_testing<SUI>(total_fee * 2, scenario.ctx()); // Sufficient base tokens for fees
        let mut quote_coin = mint_for_testing<USDC>(0, scenario.ctx()); // No quote coins needed for ask order

        // Record initial balances
        let initial_balance_manager_base = balance_manager.balance<SUI>();

        // Verify no protocol unsettled fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Verify no user unsettled fee exists initially
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Charge protocol fees with input coin fee type
        charge_protocol_fees(
            &mut fee_manager,
            &trading_fee_config,
            &pool,
            &mut balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &order_info,
            ORDER_AMOUNT,
            DISCOUNT_RATE,
            false, // deep_fee_type = false (input coin fee type)
            scenario.ctx(),
        );

        // Step 5: Verify results

        // Verify taker fees are added to protocol unsettled fees
        let final_fee_manager_balance = fee_manager.get_protocol_unsettled_fee_balance<SUI>();
        assert_eq!(final_fee_manager_balance, taker_fee);

        // Verify maker fees are added to user unsettled fees
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            maker_fee,
        );

        // Verify balance manager base balance decreased by the fee amount
        let final_balance_manager_base = balance_manager.balance<SUI>();
        assert_eq!(final_balance_manager_base, initial_balance_manager_base - total_fee);

        // Verify calculated fees are correct
        // Using input coin fee type rates: taker = 500_000 (0.05%), maker = 200_000 (0.02%)
        // 20% executed: taker_fee = 1_000_000 * 0.2 * 0.0005 = 100
        // 80% maker: maker_fee = 1_000_000 * 0.8 * 0.0002 = 160
        // 15% discount: total_fee = 260 * 0.85 = 221
        assert_eq!(taker_fee, 85); // 100 * 0.85 = 85
        assert_eq!(maker_fee, 136); // 160 * 0.85 = 136
        assert_eq!(total_fee, 221); // (100 + 160) * 0.85 = 221

        destroy(base_coin);
        destroy(quote_coin);
        return_shared(fee_manager);
        return_shared(trading_fee_config);
        return_shared(pool);
        return_shared(balance_manager);
    };

    scenario.end();
}

// === Helper Functions ===

/// Sets up a complete test environment with treasury, fee config, and deepbook infrastructure
#[test_only]
fun setup_test_environment(): (
    sui::test_scenario::Scenario,
    sui::object::ID,
    sui::object::ID,
    sui::object::ID,
) {
    let mut scenario = sui::test_scenario::begin(OWNER);

    // Setup treasury
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
        fee::init_for_testing(scenario.ctx());
    };

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        ORDER_AMOUNT * constants::float_scaling(),
        &mut scenario,
    );

    // Create pool with default fees (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        false, // whitelisted_pool = false
        false, // stable_pool = false
        &mut scenario,
    );

    // Setup fee manager
    scenario.next_tx(ALICE);
    {
        let (fee_manager, owner_cap, ticket) = deeptrade_core::fee_manager::new(scenario.ctx());
        fee_manager.share_fee_manager(ticket);
        sui::transfer::public_transfer(owner_cap, ALICE);
    };

    scenario.next_tx(ALICE);
    let fee_manager_id = sui::test_scenario::most_recent_id_shared<FeeManager>().extract();

    (scenario, pool_id, balance_manager_id, fee_manager_id)
}

/// Creates a partially executed bid order for testing (both taker and maker fees apply)
#[test_only]
fun create_partially_executed_bid_order(
    original_quantity: u64,
    executed_quantity: u64,
    pool_id: sui::object::ID,
    balance_manager_id: sui::object::ID,
): OrderInfo {
    let status = constants::partially_filled();

    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        1, // order_id
        ALICE,
        1_000_000, // price
        original_quantity,
        executed_quantity,
        status,
        true, // is_bid
        true, // fee_is_deep
    )
}

/// Creates a partially executed ask order for testing (both taker and maker fees apply)
#[test_only]
fun create_partially_executed_ask_order(
    original_quantity: u64,
    executed_quantity: u64,
    pool_id: sui::object::ID,
    balance_manager_id: sui::object::ID,
): OrderInfo {
    let status = constants::partially_filled();

    order_info::create_order_info_for_tests(
        pool_id,
        balance_manager_id,
        2, // order_id (different from bid order)
        ALICE,
        1_000_000, // price
        original_quantity,
        executed_quantity,
        status,
        false, // is_bid
        false, // fee_is_deep
    )
}
