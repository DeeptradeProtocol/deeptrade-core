#[test_only]
module deeptrade_core::get_sui_per_deep_tests;

use deepbook::balance_manager_tests::create_acct_and_share_with_funds;
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{setup_test, setup_reference_pool};
use deeptrade_core::get_sui_per_deep_from_oracle_tests::{
    new_deep_price_object,
    new_sui_price_object
};
use deeptrade_core::helper::{
    get_sui_per_deep,
    get_sui_per_deep_from_oracle,
    get_sui_per_deep_from_reference_pool
};
use pyth::price_info;
use std::unit_test::assert_eq;
use sui::clock;
use sui::sui::SUI;
use sui::test_scenario::{begin, end, return_shared};
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;

#[test]
/// Test case 1: Oracle price higher than reference pool price
fun oracle_price_higher_than_reference_pool() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let clock = clock::create_for_testing(scenario.ctx());

    // Create reference pool with price 180 SUI per DEEP
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Create oracle price objects with higher price (200 SUI per DEEP)
    let deep_price = new_deep_price_object(
        &mut scenario,
        200, // DEEP price magnitude (200 USD per DEEP)
        false, // positive
        1, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        1, // SUI price magnitude (1 USD per SUI)
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );

    // Test the function
    scenario.next_tx(ALICE);
    {
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);

        let result = get_sui_per_deep<DEEP, SUI>(
            &deep_price,
            &sui_price,
            &reference_pool,
            &clock,
        );

        // Oracle calculation: 200 USD/DEEP / 1 USD/SUI = 200 SUI per DEEP
        // Reference pool: ~180 SUI per DEEP (from setup_reference_pool)
        // Function should return 200 (oracle price, which is higher)
        assert_eq!(result, 200_000_000_000_000);

        return_shared(reference_pool);
    };

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    end(scenario);
}

#[test]
/// Test case 2: Reference pool price higher than oracle price
fun reference_pool_price_higher_than_oracle() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let clock = clock::create_for_testing(scenario.ctx());

    // Create reference pool with price 180 SUI per DEEP
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Create oracle price objects with lower price (0.1 SUI per DEEP)
    let deep_price = new_deep_price_object(
        &mut scenario,
        1, // DEEP price magnitude (1 USD per DEEP)
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        10, // SUI price magnitude (10 USD per SUI)
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );

    // Test the function
    scenario.next_tx(ALICE);
    {
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);

        let result = get_sui_per_deep<DEEP, SUI>(
            &deep_price,
            &sui_price,
            &reference_pool,
            &clock,
        );

        // Oracle calculation: 1 USD/DEEP / 10 USD/SUI = 0.1 SUI per DEEP = 100_000_000_000
        // Reference pool: 180 SUI per DEEP = 180_000_000_000
        // Function should return 180_000_000_000 (reference pool price, which is higher)
        assert_eq!(result, 180_000_000_000);

        return_shared(reference_pool);
    };

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    end(scenario);
}

#[test]
/// Test case 3: Equal prices from oracle and reference pool
fun equal_prices_from_oracle_and_reference_pool() {
    let mut scenario = begin(OWNER);

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let clock = clock::create_for_testing(scenario.ctx());

    // Create reference pool with price 180 SUI per DEEP
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        balance_manager_id,
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    let deep_price = new_deep_price_object(
        &mut scenario,
        180, // DEEP price magnitude
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        1000, // SUI price magnitude
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        clock::timestamp_ms(&clock),
    );

    // Test the function
    scenario.next_tx(ALICE);
    {
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);

        // Get individual prices
        let oracle_price = get_sui_per_deep_from_oracle(&deep_price, &sui_price, &clock);
        let reference_pool_price = get_sui_per_deep_from_reference_pool<DEEP, SUI>(
            &reference_pool,
            &clock,
        );

        // Verify both individual functions return the same value
        assert_eq!(oracle_price, reference_pool_price);

        // Test the main function
        let result = get_sui_per_deep<DEEP, SUI>(
            &deep_price,
            &sui_price,
            &reference_pool,
            &clock,
        );

        // Function should return the same value as both individual functions
        assert_eq!(result, oracle_price);
        assert_eq!(result, reference_pool_price);

        return_shared(reference_pool);
    };

    // Cleanup
    clock::destroy_for_testing(clock);
    price_info::destroy(deep_price);
    price_info::destroy(sui_price);
    end(scenario);
}
