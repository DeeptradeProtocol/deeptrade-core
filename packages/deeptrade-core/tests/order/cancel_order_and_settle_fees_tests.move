#[test_only]
module deeptrade_core::cancel_order_and_settle_fees_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{
    setup_test,
    setup_pool_with_default_fees_and_reference_pool,
    place_limit_order
};
use deeptrade_core::dt_order::cancel_order_and_settle_fees;
use deeptrade_core::fee_manager::{Self, FeeManager};
use deeptrade_core::treasury;
use std::unit_test::assert_eq;
use sui::balance;
use sui::clock::Clock;
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

    // Step 1: Place order and add unsettled fees
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);

        // Place a limit order
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1, // client_order_id
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(), // price
            100 * constants::float_scaling(), // quantity
            true, // is_bid
            true, // pay_with_deep
            constants::max_u64(), // expire_timestamp
            &mut scenario,
        );

        // Add unsettled fees to this order
        let fee_amount = 1000u64;
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());

        // Verify the fee was added
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            fee_amount,
        );

        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Test cancel_order_and_settle_fees
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<treasury::Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();

        // Test cancel_order_and_settle_fees
        let settled_coin = cancel_order_and_settle_fees<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &mut pool,
            &mut balance_manager,
            order_id,
            &clock,
            scenario.ctx(),
        );

        // Since the order is completely unfilled, we should get all fees back
        assert_eq!(settled_coin.value(), 1000u64);

        // Verify the unsettled fee is destroyed
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                object::id(&pool),
                object::id(&balance_manager),
                order_id,
            ),
            false,
        );

        // Verify the order is no longer in open orders
        let open_orders = pool.account_open_orders(&balance_manager);
        assert_eq!(open_orders.contains(&order_id), false);

        // Clean up
        destroy(settled_coin);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with treasury and deepbook infrastructure.
/// Returns (scenario, pool_id, balance_manager_id, fee_manager_id) ready for testing.
///
/// This common setup will be reused across all cancel_order_and_settle_fees tests:
/// - Initializes treasury with init_for_testing
/// - Creates deepbook registry and clock
/// - Creates funded balance manager for ALICE
/// - Creates SUI/USDC pool with reference DEEP pricing
/// - Creates FeeManager for ALICE
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

    (scenario, pool_id, balance_manager_id, fee_manager_id)
}
