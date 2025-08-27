#[test_only]
module deeptrade_core::update_pool_specific_fees_tests;

use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{setup_test, setup_pool_with_default_fees_and_reference_pool};
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::get_ticket_ready_for_consumption;
use deeptrade_core::fee::{
    Self,
    TradingFeeConfig,
    PoolFeesUpdated,
    new_pool_fee_config,
    unwrap_pool_fees_updated_event,
    get_pool_fee_config
};
use deeptrade_core::ticket::{
    ETicketTypeMismatch,
    TicketDestroyed,
    unwrap_ticket_destroyed_event,
    update_default_fees_ticket_type,
    update_pool_specific_fees_ticket_type
};
use deeptrade_core::trading_fee_config_init_tests::setup_with_trading_fee_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::event;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use token::deep::DEEP;

const NEW_TAKER_FEE: u64 = 1_500_000;
const NEW_MAKER_FEE: u64 = 700_000;

const MAX_TAKER_FEE_RATE: u64 = 2_000_000;
const MAX_DISCOUNT_RATE: u64 = 1_000_000_000;

/// Test successful update of pool-specific fees
#[test]
fun test_update_pool_specific_fees_success() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, ticket_id, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let new_fees = new_pool_fee_config(
        NEW_TAKER_FEE,
        NEW_MAKER_FEE,
        NEW_TAKER_FEE,
        NEW_MAKER_FEE,
        0,
    );

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    let config_id = sui::object::id(&config);
    let old_fees = get_pool_fee_config(&config, &pool);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        new_fees,
        &clock,
        scenario.ctx(),
    );

    let consumed_ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(consumed_ticket_events.length() == 1, 1);
    let (event_ticket_id, _, _) = unwrap_ticket_destroyed_event(&consumed_ticket_events[0]);
    assert!(event_ticket_id == ticket_id, 2);

    let updated_fee_events = event::events_by_type<PoolFeesUpdated>();
    assert!(updated_fee_events.length() == 1, 3);
    let (
        event_config_id,
        event_pool_id,
        event_old_fees,
        event_new_fees,
    ) = unwrap_pool_fees_updated_event(
        &updated_fee_events[0],
    );

    assert!(event_config_id == config_id, 4);
    assert!(event_pool_id == pool_id, 5);
    assert!(event_old_fees == old_fees, 6);
    assert!(event_new_fees == new_fees, 7);

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

/// Test failure when updating pool-specific fees with an incorrect ticket type
#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
fun test_update_pool_specific_fees_fails_wrong_type() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let wrong_ticket_type = update_default_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(
        &mut scenario,
        wrong_ticket_type,
    );

    let new_fees = new_pool_fee_config(0, 0, 0, 0, 0);

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        new_fees,
        &clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// === View Function Logic Tests ===
/// Test that `get_pool_fee_config` returns the default fees for a pool with no specific config.
#[test]
fun test_get_pool_fee_config_returns_default_when_no_specific_config() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    scenario.next_tx(multisig_address);
    let config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    let default_fees = fee::default_fees(&config);
    let received_fees = get_pool_fee_config(&config, &pool);

    assert!(received_fees == default_fees, 1);

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    scenario.end();
}

/// Test that `get_pool_fee_config` returns the correct specific fees after they have been set.
#[test]
fun test_get_pool_fee_config_returns_specific_fees() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    // 1. Set the specific fees
    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let specific_fees = new_pool_fee_config(NEW_TAKER_FEE, NEW_MAKER_FEE, 0, 0, 0);

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        specific_fees,
        &clock,
        scenario.ctx(),
    );

    // 2. Verify `get_pool_fee_config` returns the fees we just set
    let received_fees = get_pool_fee_config(&config, &pool);
    assert!(received_fees == specific_fees, 1);

    // 3. Just to be sure, also verify they are different from the default fees
    let default_fees = fee::default_fees(&config);
    assert!(received_fees != default_fees, 2);

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// === Validation Failure Tests ===

/// Test that updating specific fees fails if the taker fee rate exceeds the maximum allowed.
#[test]
#[expected_failure(abort_code = fee::EFeeOutOfRange)]
fun test_update_specific_fails_if_taker_fee_exceeds_max() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let invalid_fees = new_pool_fee_config(
        MAX_TAKER_FEE_RATE + 1000, // Exceeds the maximum, multiple of 1000
        0,
        0,
        0,
        0,
    );

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        invalid_fees,
        &clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

/// Test that updating specific fees fails if the maker fee is greater than the taker fee.
#[test]
#[expected_failure(abort_code = fee::EInvalidFeeHierarchy)]
fun test_update_specific_fails_if_maker_exceeds_taker() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let invalid_fees = new_pool_fee_config(
        500_000,
        600_000,
        0,
        0,
        0,
    );

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        invalid_fees,
        &clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

/// Test that updating specific fees fails if a fee rate does not adhere to the precision multiple.
#[test]
#[expected_failure(abort_code = fee::EInvalidFeePrecision)]
fun test_update_specific_fails_with_invalid_precision() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let invalid_fees = new_pool_fee_config(1_000_001, 0, 0, 0, 0);

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        invalid_fees,
        &clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

/// Test that updating specific fees fails if the discount rate exceeds the maximum.
#[test]
#[expected_failure(abort_code = fee::EDiscountOutOfRange)]
fun test_update_specific_fails_if_discount_exceeds_max() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario, pool_id) = setup(multisig_address);

    let ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let invalid_fees = new_pool_fee_config(
        0,
        0,
        0,
        0,
        MAX_DISCOUNT_RATE + 1000,
    );

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);

    fee::update_pool_specific_fees(
        &mut config,
        ticket,
        &pool,
        invalid_fees,
        &clock,
        scenario.ctx(),
    );

    test_scenario::return_shared(pool);
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// === Helper Functions ===

#[test_only]
fun setup(multisig_address: address): (Scenario, ID) {
    let mut scenario = setup_with_admin_cap(multisig_address);
    setup_with_trading_fee_config(&mut scenario, multisig_address);

    scenario.next_tx(multisig_address);

    let registry_id = setup_test(multisig_address, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        multisig_address,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );
    let pool_id = setup_pool_with_default_fees_and_reference_pool<SUI, USDC, SUI, DEEP>(
        multisig_address,
        registry_id,
        balance_manager_id,
        &mut scenario,
    );

    (scenario, pool_id)
}
