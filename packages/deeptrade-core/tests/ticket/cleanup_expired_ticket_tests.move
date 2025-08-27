#[test_only]
module deeptrade_core::cleanup_expired_ticket_tests;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::ticket::{Self, AdminTicket, ETicketNotExpired};
use multisig::multisig_test_utils::{
    get_test_multisig_address,
    get_test_multisig_pks,
    get_test_multisig_threshold,
    get_test_multisig_weights
};
use sui::clock;
use sui::test_scenario::Scenario;

const TICKET_TYPE: u8 = 0;
// Durations in milliseconds
const MILLISECONDS_PER_DAY: u64 = 86_400_000;
const TICKET_DELAY_DURATION: u64 = MILLISECONDS_PER_DAY * 2; // 2 days
const TICKET_ACTIVE_DURATION: u64 = MILLISECONDS_PER_DAY * 3; // 3 days

// TODO: Move it to a helper section of create ticket tests module
// and make it more generic, so it would accept owner and ticket type
#[test_only]
fun create_ticket(scenario: &mut Scenario) {
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);

    let clock = clock::create_for_testing(scenario.ctx());
    let admin_cap = scenario.take_from_sender<AdminCap>();

    ticket::create_ticket(
        &admin_cap,
        TICKET_TYPE,
        get_test_multisig_pks(),
        get_test_multisig_weights(),
        get_test_multisig_threshold(),
        &clock,
        scenario.ctx(),
    );

    clock::destroy_for_testing(clock);
    scenario.return_to_sender(admin_cap);
}

#[test]
/// Test that an expired ticket can be cleaned up
fun test_cleanup_expired_ticket_success() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    create_ticket(&mut scenario);

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
    create_ticket(&mut scenario);

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
