#[test_only]
module deeptrade_core::ticket_lifecycle_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::create_ticket_with_multisig;
use deeptrade_core::ticket::{
    Self,
    AdminTicket,
    ETicketExpired,
    ETicketNotReady,
    ETicketOwnerMismatch,
    ETicketTypeMismatch,
    ticket_active_duration,
    ticket_delay_duration,
    update_default_fees_ticket_type,
    update_pool_creation_protocol_fee_ticket_type,
    update_pool_specific_fees_ticket_type,
    withdraw_coverage_fee_ticket_type,
    withdraw_deep_reserves_ticket_type,
    withdraw_protocol_fee_ticket_type
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::test_scenario::{Self, Scenario};

#[test]
/// Test is_ticket_ready logic across its lifecycle
fun test_is_ticket_ready() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    let mut clock = clock::create_for_testing(scenario.ctx());

    // Immediately after creation, it's not ready
    assert!(!ticket.is_ticket_ready(&clock), 1);

    // Advance time to just before it's ready
    let delay = ticket_delay_duration();
    clock.increment_for_testing(delay - 1);
    assert!(!ticket.is_ticket_ready(&clock), 2);

    // Advance time to exactly when it's ready
    clock.increment_for_testing(1);
    assert!(ticket.is_ticket_ready(&clock), 3);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

#[test]
/// Test is_ticket_expired logic across its lifecycle
fun test_is_ticket_expired() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    let mut clock = clock::create_for_testing(scenario.ctx());

    // Immediately after creation, it's not expired
    assert!(!ticket.is_ticket_expired(&clock), 1);

    // Advance time to just before it expires
    let total_duration = ticket_delay_duration() + ticket_active_duration();
    clock.increment_for_testing(total_duration - 1);
    assert!(!ticket.is_ticket_expired(&clock), 2);

    // Advance time to exactly when it expires
    clock.increment_for_testing(1);
    assert!(ticket.is_ticket_expired(&clock), 3);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

#[test]
/// Test validate_ticket logic succeeds for all ticket types when conditions are met
fun test_validate_ticket_success_all_types() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    let ticket_types = vector[
        withdraw_deep_reserves_ticket_type(),
        withdraw_protocol_fee_ticket_type(),
        withdraw_coverage_fee_ticket_type(),
        update_pool_creation_protocol_fee_ticket_type(),
        update_default_fees_ticket_type(),
        update_pool_specific_fees_ticket_type(),
    ];

    let mut i = 0;
    while (i < ticket_types.length()) {
        let ticket_type = ticket_types[i];
        run_validate_ticket_success(&mut scenario, ticket_type);
        i = i + 1;
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketOwnerMismatch)]
/// Test validate_ticket fails for wrong owner
fun test_validate_ticket_fails_wrong_owner() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    scenario.next_tx(@0xFACE); // Switch user

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    // Validation should fail due to owner mismatch
    ticket.validate_ticket(ticket_type, &clock, scenario.ctx());

    // Cleanup
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
/// Test validate_ticket fails for wrong type
fun test_validate_ticket_fails_wrong_type() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    // Validation should fail due to type mismatch
    ticket.validate_ticket(ticket_type + 1, &clock, scenario.ctx());

    // Cleanup
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketNotReady)]
/// Test validate_ticket fails if not ready (delay duration has not passed)
fun test_validate_ticket_fails_not_ready() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    let clock = clock::create_for_testing(scenario.ctx());

    // Don't advance time, so it's not ready
    // Validation should fail
    ticket.validate_ticket(ticket_type, &clock, scenario.ctx());

    // Cleanup
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketExpired)]
/// Test validate_ticket fails if expired (active duration has passed)
fun test_validate_ticket_fails_expired() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    let ticket_type = withdraw_deep_reserves_ticket_type();
    let ticket = create_and_take_ticket(&mut scenario, ticket_type);

    // Advance time to make it expire
    let total_duration = ticket_delay_duration() + ticket_active_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(total_duration);

    // Validation should fail
    ticket.validate_ticket(ticket_type, &clock, scenario.ctx());

    // Cleanup
    clock::destroy_for_testing(clock);
    test_scenario::return_shared(ticket);
    scenario.end();
}

// === Helper Functions ===
#[test_only]
fun create_and_take_ticket(scenario: &mut Scenario, ticket_type: u8): AdminTicket {
    create_ticket_with_multisig(scenario, ticket_type);
    test_scenario::next_tx(scenario, get_test_multisig_address());
    scenario.take_shared<AdminTicket>()
}

#[test_only]
fun run_validate_ticket_success(scenario: &mut Scenario, ticket_type: u8) {
    let ticket = create_and_take_ticket(scenario, ticket_type);
    let delay = ticket_delay_duration();

    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    ticket.validate_ticket(ticket_type, &clock, scenario.ctx());

    // Cleanup
    ticket::destroy_ticket(ticket, &clock);
    clock::destroy_for_testing(clock);
}
