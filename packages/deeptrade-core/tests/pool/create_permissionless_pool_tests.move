#[test_only]
module deeptrade_core::create_permissionless_pool_tests;

use deepbook::constants;
use deepbook::pool_tests::setup_test;
use deepbook::registry::Registry;
use deeptrade_core::dt_pool::{
    Self as pool,
    PoolCreated,
    ENotEnoughFee,
    ECreationFeeTooLarge,
    PoolCreationConfig
};
use deeptrade_core::pool_init_tests;
use deeptrade_core::treasury::{Self, Treasury};
use sui::balance::{Self, Balance};
use sui::coin;
use sui::event;
use sui::test_scenario::{Self, Scenario, next_tx};
use token::deep::DEEP;

const USER: address = @0xCAFE;

const TICK_SIZE: u64 = 1000;
const LOT_SIZE: u64 = 1000;
const MIN_SIZE: u64 = 1000;

#[test_only]
public struct DUMMY_BASE has drop {}

#[test_only]
public struct DUMMY_QUOTE has drop {}

#[test]
fun test_create_pool_success() {
    let (mut scenario, mut registry, mut treasury, config, mut deep_balance) = setup();

    scenario.next_tx(USER);
    {
        let deepbook_fee = constants::pool_creation_fee();
        let protocol_fee = pool::pool_creation_protocol_fee(&config);
        let total_fee = deepbook_fee + protocol_fee;

        let treasury_balance_before = treasury::get_protocol_fee_balance<DEEP>(&treasury);

        let fee_coin = coin::from_balance(
            balance::split(&mut deep_balance, total_fee),
            scenario.ctx(),
        );

        let pool_id = pool::create_permissionless_pool<DUMMY_BASE, DUMMY_QUOTE>(
            &mut treasury,
            &config,
            &mut registry,
            fee_coin,
            TICK_SIZE,
            LOT_SIZE,
            MIN_SIZE,
            scenario.ctx(),
        );

        let treasury_balance_after = treasury::get_protocol_fee_balance<DEEP>(&treasury);

        assert!(treasury_balance_after == treasury_balance_before + protocol_fee, 0);

        // Verify event
        let pool_created_event_raw = event::events_by_type<PoolCreated<DUMMY_BASE, DUMMY_QUOTE>>()[
            0,
        ];
        let (
            event_config_id,
            event_pool_id,
            event_tick_size,
            event_lot_size,
            event_min_size,
        ) = pool::unwrap_pool_created_event<DUMMY_BASE, DUMMY_QUOTE>(
            &pool_created_event_raw,
        );

        assert!(event_config_id == object::id(&config), 1);
        assert!(event_pool_id == pool_id, 2);
        assert!(event_tick_size == TICK_SIZE, 3);
        assert!(event_lot_size == LOT_SIZE, 4);
        assert!(event_min_size == MIN_SIZE, 5);

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(config);
        test_scenario::return_shared(registry);
    };

    deep_balance.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ENotEnoughFee)]
fun test_create_pool_fails_fee_too_low() {
    let (mut scenario, mut registry, mut treasury, config, mut deep_balance) = setup();

    scenario.next_tx(USER);
    {
        let deepbook_fee = constants::pool_creation_fee();
        let protocol_fee = pool::pool_creation_protocol_fee(&config);
        let total_fee = deepbook_fee + protocol_fee;

        // Fee is one less than required
        let fee_coin = coin::from_balance(
            balance::split(&mut deep_balance, total_fee - 1),
            scenario.ctx(),
        );

        pool::create_permissionless_pool<DUMMY_BASE, DUMMY_QUOTE>(
            &mut treasury,
            &config,
            &mut registry,
            fee_coin,
            TICK_SIZE,
            LOT_SIZE,
            MIN_SIZE,
            scenario.ctx(),
        );

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(config);
        test_scenario::return_shared(registry);
    };

    deep_balance.destroy_for_testing();
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ECreationFeeTooLarge)]
fun test_create_pool_fails_fee_too_high() {
    let (mut scenario, mut registry, mut treasury, config, mut deep_balance) = setup();

    scenario.next_tx(USER);
    {
        let deepbook_fee = constants::pool_creation_fee();
        let protocol_fee = pool::pool_creation_protocol_fee(&config);
        let total_fee = deepbook_fee + protocol_fee;

        // Fee is one more than required
        let fee_coin = coin::from_balance(
            balance::split(&mut deep_balance, total_fee + 1),
            scenario.ctx(),
        );

        pool::create_permissionless_pool<DUMMY_BASE, DUMMY_QUOTE>(
            &mut treasury,
            &config,
            &mut registry,
            fee_coin,
            TICK_SIZE,
            LOT_SIZE,
            MIN_SIZE,
            scenario.ctx(),
        );

        test_scenario::return_shared(treasury);
        test_scenario::return_shared(config);
        test_scenario::return_shared(registry);
    };

    deep_balance.destroy_for_testing();
    scenario.end();
}

// === Helper Functions ===

#[test_only]
fun setup(): (Scenario, Registry, Treasury, PoolCreationConfig, Balance<DEEP>) {
    let mut scenario = test_scenario::begin(USER);

    // Initialise treasury, pool config, registry
    treasury::init_for_testing(scenario.ctx());
    pool_init_tests::setup_with_pool_creation_config(&mut scenario, USER);
    let registry_id = setup_test(USER, &mut scenario);

    // Mint some DEEP coins for the user to pay fees
    let deep_coins = coin::mint_for_testing<DEEP>(1_000_000_000_000, scenario.ctx());

    scenario.next_tx(USER);
    let treasury: Treasury = scenario.take_shared<Treasury>();
    let config: PoolCreationConfig = scenario.take_shared<PoolCreationConfig>();
    let registry: Registry = scenario.take_shared_by_id<Registry>(registry_id);

    (scenario, registry, treasury, config, deep_coins.into_balance())
}
