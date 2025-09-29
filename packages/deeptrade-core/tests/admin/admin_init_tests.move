#[test_only]
module deeptrade_core::admin_init_tests;

use deeptrade_core::admin::{Self, AdminCap};
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use std::unit_test::assert_eq;
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and transfers the AdminCap.
fun init_logic_creates_and_transfers_admin_cap_to_publisher() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        admin::init_for_testing(scenario.ctx());
    };

    // End Tx 0 and start Tx 1 to make the transferred object available.
    scenario.next_tx(publisher);
    {
        // Explicitly assert that an AdminCap object exists in the publisher's inventory.
        assert_eq!(scenario.has_most_recent_for_sender<AdminCap>(), true);

        // Now, take the object. This call is still necessary to interact with or
        // clean up the object from the test scenario.
        let admin_cap = scenario.take_from_sender<AdminCap>();

        // Return the AdminCap to the scenario's state.
        scenario.return_to_sender(admin_cap);
    };
    test_scenario::end(scenario);
}

/// Initializes admin and gives the AdminCap to the OWNER.
#[test_only]
public fun setup_with_admin_cap(owner: address): test_scenario::Scenario {
    let mut scenario = setup_with_initialized_config();
    scenario.next_tx(owner);
    {
        admin::init_for_testing(scenario.ctx());
    };

    scenario
}
