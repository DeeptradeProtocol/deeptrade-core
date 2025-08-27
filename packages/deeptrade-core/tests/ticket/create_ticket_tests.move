#[test_only]
module deeptrade_core::create_ticket_tests;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::ticket::{Self, AdminTicket, ESenderIsNotMultisig, TicketCreated};
use multisig::multisig_test_utils::{
    get_test_multisig_address,
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold
};
use sui::clock;
use sui::event;
use sui::test_scenario::{Self, Scenario, return_shared};

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

        ticket::create_ticket(
            &admin_cap,
            TICKET_TYPE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            &clock,
            test_scenario::ctx(&mut scenario),
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
    };

    scenario.next_tx(multisig_address);
    {
        let ticket = test_scenario::take_shared<AdminTicket>(&scenario);
        assert!(ticket.owner() == multisig_address, 1);
        assert!(ticket.ticket_type() == TICKET_TYPE, 2);
        assert!(ticket.created_at() == CLOCK_TIMESTAMP_MS, 3);

        assert!(ticket_id_from_event == object::id(&ticket), 2);
        assert!(ticket_type_from_event == ticket.ticket_type(), 3);

        return_shared(ticket);
    };

    scenario.end();
}

#[test]
#[expected_failure(abort_code = ESenderIsNotMultisig)]
/// Test that ticket creation fails if the sender is not the derived multisig address.
fun create_ticket_fails_if_sender_not_multisig() {
    let owner = @0xDEED;
    let (mut scenario) = setup_with_admin_cap(owner);

    // NOTE: We do NOT switch the sender. The sender remains the OWNER,
    // which does not match the derived multisig address.
    test_scenario::next_tx(&mut scenario, owner);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = scenario.take_from_sender<AdminCap>();

        // This should abort
        ticket::create_ticket(
            &admin_cap,
            TICKET_TYPE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            &clock,
            test_scenario::ctx(&mut scenario),
        );

        clock::destroy_for_testing(clock);
        scenario.return_to_sender(admin_cap);
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

    ticket::create_ticket(
        &admin_cap,
        ticket_type,
        get_test_multisig_pks(),
        get_test_multisig_weights(),
        get_test_multisig_threshold(),
        &clock,
        scenario.ctx(),
    );

    clock::destroy_for_testing(clock);
    scenario.return_to_sender(admin_cap);

    // We keep it here to make sure the ticket is available from Global Inventory in the next test
    scenario.next_tx(multisig_address);
}
