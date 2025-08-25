#[test_only]
module deeptrade_core::create_ticket_tests;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::ticket::{Self, AdminTicket, ESenderIsNotMultisig};
use multisig::multisig_test_utils::{
    get_test_multisig_address,
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold
};
use sui::clock;
use sui::test_scenario;

const TICKET_TYPE: u8 = 0;
const CLOCK_TIMESTAMP_MS: u64 = 1756071906000;

#[test]
/// Test that a ticket is created successfully when the sender is a valid multisig address.
fun create_ticket_success_with_multisig() {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    // Switch to the derived multisig address to send the transaction
    test_scenario::next_tx(&mut scenario, multisig_address);
    {
        let mut clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock.set_for_testing(CLOCK_TIMESTAMP_MS);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

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
        test_scenario::return_to_sender(&scenario, admin_cap);
    };

    test_scenario::next_tx(&mut scenario, multisig_address);
    {
        let ticket = test_scenario::take_shared<AdminTicket>(&scenario);
        assert!(ticket::owner(&ticket) == multisig_address, 1);
        assert!(ticket::ticket_type(&ticket) == TICKET_TYPE, 2);
        assert!(ticket::created_at(&ticket) == CLOCK_TIMESTAMP_MS, 3);

        test_scenario::return_shared(ticket);
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
        let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

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
        test_scenario::return_to_sender(&scenario, admin_cap);
    };

    scenario.end();
}
