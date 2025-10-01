#[test_only]
module deeptrade_core::create_ticket_tests;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use deeptrade_core::ticket::{Self, AdminTicket, TicketCreated, ticket_delay_duration};
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::clock::{Self, Clock};
use sui::event;
use sui::test_scenario::{Scenario, return_shared};

const TICKET_TYPE: u8 = 0;
const CLOCK_TIMESTAMP_MS: u64 = 1756071906000;

#[test]
/// Test that a ticket is created successfully when the sender is a valid multisig address.
fun create_ticket_success_with_multisig() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    let ticket_id_from_event;
    let ticket_type_from_event;

    // Switch to the derived multisig address to send the transaction
    scenario.next_tx(multisig_address);
    {
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock.set_for_testing(CLOCK_TIMESTAMP_MS);
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let config = scenario.take_shared<MultisigConfig>();

        ticket::create_ticket(
            &config,
            &admin_cap,
            TICKET_TYPE,
            &clock,
            scenario.ctx(),
        );

        // Check that the event was emitted correctly
        let ticket_events = event::events_by_type<TicketCreated>();
        assert!(ticket_events.length() == 1);
        let ticket_created_event = ticket_events[0];
        let (ticket_id, ticket_type) = ticket_created_event.unwrap_ticket_created_event();
        ticket_id_from_event = ticket_id;
        ticket_type_from_event = ticket_type;

        clock::destroy_for_testing(clock);
        scenario.return_to_sender(admin_cap);
        return_shared(config);
    };

    scenario.next_tx(multisig_address);
    {
        let ticket = scenario.take_shared<AdminTicket>();
        assert_eq!(ticket.owner(), multisig_address);
        assert_eq!(ticket.ticket_type(), TICKET_TYPE);
        assert_eq!(ticket.created_at(), CLOCK_TIMESTAMP_MS);

        assert!(ticket_id_from_event == object::id(&ticket), 2);
        assert!(ticket_type_from_event == ticket.ticket_type(), 3);

        return_shared(ticket);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
/// Test that ticket creation fails if the sender is not the derived multisig address.
fun create_ticket_fails_if_sender_not_multisig() {
    let owner = @0xDEED;
    let (mut scenario) = setup_with_admin_cap(owner);

    // NOTE: We do NOT switch the sender. The sender remains the OWNER,
    // which does not match the derived multisig address.
    scenario.next_tx(owner);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = scenario.take_from_sender<AdminCap>();
        let config = scenario.take_shared<MultisigConfig>();

        // This should abort
        ticket::create_ticket(
            &config,
            &admin_cap,
            TICKET_TYPE,
            &clock,
            scenario.ctx(),
        );

        clock::destroy_for_testing(clock);
        scenario.return_to_sender(admin_cap);
        return_shared(config);
    };

    scenario.end();
}

// === Helper Functions ===
#[test_only]
public fun create_ticket_with_multisig(scenario: &mut Scenario, ticket_type: u8) {
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);

    let clock = clock::create_for_testing(scenario.ctx());
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let config = scenario.take_shared<MultisigConfig>();

    ticket::create_ticket(
        &config,
        &admin_cap,
        ticket_type,
        &clock,
        scenario.ctx(),
    );

    clock::destroy_for_testing(clock);
    scenario.return_to_sender(admin_cap);
    return_shared(config);

    // We keep it here to make sure the ticket is available from Global Inventory in the next test
    scenario.next_tx(multisig_address);
}

/// Create a ticket and increment the clock to make it ready for consumption.
#[test_only]
public fun get_ticket_ready_for_consumption(
    scenario: &mut Scenario,
    ticket_type: u8,
): (AdminTicket, ID, Clock) {
    create_ticket_with_multisig(scenario, ticket_type);
    let ticket = scenario.take_shared<AdminTicket>();
    let ticket_id = object::id(&ticket);

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    (ticket, ticket_id, clock)
}
