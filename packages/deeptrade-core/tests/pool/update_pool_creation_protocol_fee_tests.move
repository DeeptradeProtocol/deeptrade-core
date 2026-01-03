#[test_only]
module deeptrade_core::update_pool_creation_protocol_fee_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::get_ticket_ready_for_consumption;
use deeptrade_core::dt_pool::{
    Self as pool,
    PoolCreationConfig,
    PoolCreationProtocolFeeUpdated,
    unwrap_pool_creation_protocol_fee_updated_event,
    default_pool_creation_protocol_fee,
    pool_creation_protocol_fee,
    EPoolCreationFeeOutOfRange
};
use deeptrade_core::pool_init_tests::setup_with_pool_creation_config;
use deeptrade_core::ticket::{
    ETicketTypeMismatch,
    TicketDestroyed,
    unwrap_ticket_destroyed_event,
    update_pool_creation_protocol_fee_ticket_type,
    update_default_fees_ticket_type
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::event;
use sui::test_scenario::{Self, Scenario};

const NEW_FEE: u64 = 200_000_000;
const FEE_TOO_HIGH: u64 = 500_000_001;

/// Test successful update of the pool creation protocol fee
#[test]
fun test_update_pool_creation_protocol_fee_success() {
    let (mut scenario) = setup();
    let multisig_address = get_test_multisig_address();

    let ticket_type = update_pool_creation_protocol_fee_ticket_type();
    let (ticket, ticket_id, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    scenario.next_tx(multisig_address);
    let mut config: PoolCreationConfig = scenario.take_shared<PoolCreationConfig>();
    let config_id = object::id(&config);
    pool::update_pool_creation_protocol_fee(
        &mut config,
        ticket,
        NEW_FEE,
        &clock,
        scenario.ctx(),
    );

    // Verify events
    let consumed_ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(consumed_ticket_events.length() == 1, 1);
    let (event_ticket_id, _, _) = unwrap_ticket_destroyed_event(&consumed_ticket_events[0]);
    assert!(event_ticket_id == ticket_id, 2);

    let updated_fee_events = event::events_by_type<PoolCreationProtocolFeeUpdated>();
    assert!(updated_fee_events.length() == 1, 3);
    let (event_config_id, old_fee, new_fee) = unwrap_pool_creation_protocol_fee_updated_event(
        &updated_fee_events[0],
    );
    assert!(event_config_id == config_id, 4);
    assert!(old_fee == default_pool_creation_protocol_fee(), 5);
    assert!(new_fee == NEW_FEE, 6);

    // Verify config state
    assert!(pool_creation_protocol_fee(&config) == NEW_FEE, 7);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(config);
    scenario.end();
}

/// Test failure when updating fee with an incorrect ticket type
#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
fun test_update_pool_creation_protocol_fee_fails_wrong_type() {
    let (mut scenario) = setup();
    let multisig_address = get_test_multisig_address();

    // Create a ticket of the wrong type
    let wrong_ticket_type = update_default_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(
        &mut scenario,
        wrong_ticket_type,
    );

    scenario.next_tx(multisig_address);
    let mut config: PoolCreationConfig = scenario.take_shared<PoolCreationConfig>();
    pool::update_pool_creation_protocol_fee(
        &mut config,
        ticket,
        NEW_FEE,
        &clock,
        scenario.ctx(),
    );

    // Cleanup should not be reached
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(config);
    scenario.end();
}

/// Test failure when updating fee that is too high
#[test]
#[expected_failure(abort_code = EPoolCreationFeeOutOfRange)]
fun test_update_pool_creation_protocol_fee_fails_fee_too_high() {
    let (mut scenario) = setup();
    let multisig_address = get_test_multisig_address();

    let ticket_type = update_pool_creation_protocol_fee_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    scenario.next_tx(multisig_address);
    let mut config: PoolCreationConfig = scenario.take_shared<PoolCreationConfig>();
    pool::update_pool_creation_protocol_fee(
        &mut config,
        ticket,
        FEE_TOO_HIGH,
        &clock,
        scenario.ctx(),
    );

    // Cleanup should not be reached
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(config);
    scenario.end();
}

// === Helper Functions ===
/// Setup a scenario with a PoolCreationConfig object
#[test_only]
fun setup(): Scenario {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    setup_with_pool_creation_config(&mut scenario, multisig_address);

    scenario
}
