#[test_only]
module deeptrade_core::get_sui_per_deep_from_reference_pool_tests;

use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::{Self, Pool};
use deepbook::pool_tests::{
    setup_test,
    setup_reference_pool,
    place_limit_order,
    setup_pool_with_default_fees,
    setup_pool_with_default_fees_and_reference_pool
};
use deepbook::registry::{Self, Registry};
use deeptrade_core::helper::{
    get_sui_per_deep_from_reference_pool,
    EIneligibleReferencePool,
    ENoAskPrice
};
use std::unit_test::assert_eq;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

#[test]
/// Test case 1: DEEP/SUI pool - verifies direct price return
fun deep_sui_pool_returns_direct_price() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create DEEP/SUI reference pool (DEEP as base, SUI as quote)
    // This will set up a pool with DEEP per SUI price of 100
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Test the function
    scenario.next_tx(ALICE);
    {
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let clock = scenario.take_shared<Clock>();

        let sui_per_deep = get_sui_per_deep_from_reference_pool<DEEP, SUI>(
            &reference_pool,
            &clock,
        );

        // For DEEP/SUI pool (DEEP as base), the function returns the ask price directly
        // `setup_reference_pool` creates orders around the deep_multiplier (100):
        // - BID at 100 - 80 = 20 (20 SUI per DEEP)
        // - ASK at 100 + 80 = 180 (180 SUI per DEEP)
        // The "80" offset is hardcoded in deepbook's `setup_reference_pool` method.
        // `get_pool_first_ask_price` returns the ASK price: 180 SUI per DEEP.
        // Since this is a DEEP/SUI pool, the function returns the price directly.
        assert_eq!(sui_per_deep, 180_000_000_000);

        return_shared(reference_pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test]
/// Test case 2: SUI/DEEP pool - verifies price inversion logic
fun sui_deep_pool_returns_inverted_price() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create SUI/DEEP reference pool (SUI as base, DEEP as quote)
    // This will set up a pool with SUI per DEEP price of 100
    let reference_pool_id = setup_reference_pool<SUI, DEEP>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Test the function
    scenario.next_tx(ALICE);
    {
        let reference_pool = scenario.take_shared_by_id<Pool<SUI, DEEP>>(reference_pool_id);
        let clock = scenario.take_shared<Clock>();

        let sui_per_deep = get_sui_per_deep_from_reference_pool<SUI, DEEP>(
            &reference_pool,
            &clock,
        );

        // For SUI/DEEP pool (SUI as base), the function inverts the ask price
        // `setup_reference_pool` creates orders around the deep_multiplier (100):
        // - BID at 100 - 80 = 20 (20 DEEP per SUI)
        // - ASK at 100 + 80 = 180 (180 DEEP per SUI)
        // The "80" offset is hardcoded in deepbook's `setup_reference_pool` method.
        // `get_pool_first_ask_price` returns the ASK price: 180 DEEP per SUI.
        // Since this is a SUI/DEEP pool, the function inverts: 1_000_000_000 / 180 = 5_555_555
        assert_eq!(sui_per_deep, 5_555_555);

        return_shared(reference_pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EIneligibleReferencePool)]
/// Test case 3: Non-whitelisted pool - should abort
fun non_whitelisted_pool_aborts() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create non-whitelisted SUI/USDC pool with DEEP price data points
    // This function creates a non-whitelisted pool but adds the required DEEP price infrastructure
    let pool_id = setup_pool_with_default_fees_and_reference_pool<SUI, USDC, DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        &mut scenario,
    );

    // Test the function - should abort because pool is not whitelisted
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        get_sui_per_deep_from_reference_pool<SUI, USDC>(
            &pool,
            &clock,
        );

        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EIneligibleReferencePool)]
/// Test case 4: Non-registered pool - should abort
fun non_registered_pool_aborts() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create whitelisted DEEP/SUI pool
    let pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(),
        &mut scenario,
    );

    // Unregister the pool to make it non-registered
    scenario.next_tx(OWNER);
    {
        let admin_cap = registry::get_admin_cap_for_testing(scenario.ctx());
        let mut pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(pool_id);
        let mut registry = scenario.take_shared_by_id<Registry>(registry_id);

        pool::unregister_pool_admin<DEEP, SUI>(
            &mut pool,
            &mut registry,
            &admin_cap,
        );
        return_shared(pool);
        return_shared(registry);
        test_utils::destroy(admin_cap);
    };

    // Test the function - should abort because pool is not registered
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        get_sui_per_deep_from_reference_pool<DEEP, SUI>(
            &pool,
            &clock,
        );

        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EIneligibleReferencePool)]
/// Test case 5: Wrong token pair - should abort
fun wrong_token_pair_aborts() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create SUI/USDC pool (contains SUI but not DEEP)
    let pool_id = setup_reference_pool<SUI, USDC>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(),
        &mut scenario,
    );

    // Test the function - should abort because pool doesn't contain both SUI and DEEP
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        get_sui_per_deep_from_reference_pool<SUI, USDC>(
            &pool,
            &clock,
        );

        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ENoAskPrice)]
/// Test case 6: No ask price available - should abort
fun no_ask_price_aborts() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create whitelisted DEEP/SUI pool
    let pool_id = setup_pool_with_default_fees<DEEP, SUI>(
        ALICE,
        registry_id,
        true, // whitelisted = true
        false, // stable = false
        &mut scenario,
    );

    // Add only bid order (no ask orders)
    place_limit_order<DEEP, SUI>(
        ALICE,
        pool_id,
        balance_manager_id,
        1,
        constants::no_restriction(),
        constants::self_matching_allowed(),
        20 * constants::float_scaling(), // bid price
        constants::float_scaling(), // quantity
        true, // is_bid = true
        true, // pay_with_deep
        constants::max_u64(), // expire_timestamp
        &mut scenario,
    );

    // Test the function - should abort because there are no ask prices
    scenario.next_tx(ALICE);
    {
        let pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(pool_id);
        let clock = scenario.take_shared<Clock>();

        get_sui_per_deep_from_reference_pool<DEEP, SUI>(
            &pool,
            &clock,
        );

        return_shared(pool);
        return_shared(clock);
    };

    end(scenario);
}
