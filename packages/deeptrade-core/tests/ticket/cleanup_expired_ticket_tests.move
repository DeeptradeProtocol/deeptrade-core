#[test_only]
module deeptrade_core::cleanup_expired_ticket_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::create_ticket_with_multisig;
use deeptrade_core::ticket::{
    Self,
    AdminTicket,
    ETicketNotExpired,
    TicketDestroyed,
    withdraw_deep_reserves_ticket_type
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::event;
use sui::test_scenario;

// Durations in milliseconds
const MILLISECONDS_PER_DAY: u64 = 86_400_000;
const TICKET_DELAY_DURATION: u64 = MILLISECONDS_PER_DAY * 2; // 2 days
const TICKET_ACTIVE_DURATION: u64 = MILLISECONDS_PER_DAY * 3; // 3 days

#[test]
/// Test that an expired ticket can be cleaned up
fun test_cleanup_expired_ticket_success() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    let ticket_type = withdraw_deep_reserves_ticket_type();
    create_ticket_with_multisig(&mut scenario, ticket_type);

    // Get the ticket ID for later comparison
    test_scenario::next_tx(&mut scenario, multisig_address);
    let ticket = scenario.take_shared<AdminTicket>();
    let ticket_id = object::id(&ticket);
    test_scenario::return_shared(ticket);

    // Advance time to make it expire
    let total_duration = TICKET_DELAY_DURATION + TICKET_ACTIVE_DURATION;
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(total_duration);

    scenario.next_tx(@0xBEEF);
    let ticket_to_cleanup = scenario.take_shared<AdminTicket>();
    ticket_to_cleanup.cleanup_expired_ticket(&clock);
    clock::destroy_for_testing(clock);

    // Check that the event was emitted correctly
    let ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(ticket_events.length() == 1, 0);
    let ticket_destroyed_event = ticket_events[0];
    let (
        event_ticket_id,
        event_ticket_type,
        event_is_expired,
    ) = ticket_destroyed_event.unwrap_ticket_destroyed_event();

    assert!(event_ticket_id == ticket_id, 1);
    assert!(event_ticket_type == ticket_type, 2);
    assert!(event_is_expired, 3);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketNotExpired)]
/// Test that cleanup fails if the ticket is not expired
fun test_cleanup_fails_if_not_expired() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    create_ticket_with_multisig(&mut scenario, withdraw_deep_reserves_ticket_type());

    // Advance time, but not enough to expire it
    let duration = TICKET_DELAY_DURATION + TICKET_ACTIVE_DURATION - 1;
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(duration);

    scenario.next_tx(@0xBEEF);
    let ticket = scenario.take_shared<AdminTicket>();
    ticket.cleanup_expired_ticket(&clock);

    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
/// Test that the constants in the ticket module are in sync with the constants in this test module
fun test_constants_are_in_sync() {
    assert!(TICKET_DELAY_DURATION == ticket::ticket_delay_duration(), 0);
    assert!(TICKET_ACTIVE_DURATION == ticket::ticket_active_duration(), 1);
}
