#[test_only]
module deeptrade_core::cleanup_expired_ticket_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::create_ticket_with_multisig;
use deeptrade_core::ticket::{
    Self,
    AdminTicket,
    ETicketNotExpired,
    withdraw_deep_reserves_ticket_type
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;

// Durations in milliseconds
const MILLISECONDS_PER_DAY: u64 = 86_400_000;
const TICKET_DELAY_DURATION: u64 = MILLISECONDS_PER_DAY * 2; // 2 days
const TICKET_ACTIVE_DURATION: u64 = MILLISECONDS_PER_DAY * 3; // 3 days

#[test]
/// Test that an expired ticket can be cleaned up
fun test_cleanup_expired_ticket_success() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    create_ticket_with_multisig(&mut scenario, withdraw_deep_reserves_ticket_type());

    // Advance time to make it expire
    let total_duration = TICKET_DELAY_DURATION + TICKET_ACTIVE_DURATION;
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(total_duration);

    scenario.next_tx(@0xBEEF);
    let ticket = scenario.take_shared<AdminTicket>();
    ticket.cleanup_expired_ticket(&clock);
    clock::destroy_for_testing(clock);

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
    assert!(TICKET_DELAY_DURATION == ticket::get_ticket_delay_duration(), 0);
    assert!(TICKET_ACTIVE_DURATION == ticket::get_ticket_active_duration(), 1);
}
