#[test_only]
module deeptrade_core::admin_init_tests;

use deeptrade_core::admin::{Self, AdminCap};
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and transfers the AdminCap.
fun init_logic_creates_and_transfers_admin_cap_to_publisher() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        admin::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    // End Tx 0 and start Tx 1 to make the transferred object available.
    test_scenario::next_tx(&mut scenario, publisher);
    {
        // Explicitly assert that an AdminCap object exists in the publisher's inventory.
        assert!(
            test_scenario::has_most_recent_for_sender<AdminCap>(&scenario),
            1, // Error code: AdminCap not found for publisher
        );

        // Now, take the object. This call is still necessary to interact with or
        // clean up the object from the test scenario.
        let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);

        // Return the AdminCap to the scenario's state.
        test_scenario::return_to_sender(&scenario, admin_cap);
    };
    test_scenario::end(scenario);
}


/// Initializes admin and gives the AdminCap to the OWNER.
#[test_only]
public fun setup_with_admin_cap(owner: address): sui::test_scenario::Scenario {
    let mut scenario = test_scenario::begin(owner);
    {
        admin::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    scenario
}