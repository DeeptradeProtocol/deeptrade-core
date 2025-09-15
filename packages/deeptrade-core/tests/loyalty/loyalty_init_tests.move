#[test_only]
module deeptrade_core::loyalty_init_tests;

use deeptrade_core::loyalty::{Self, LoyaltyAdminCap, LoyaltyProgram};
use std::unit_test::assert_eq;
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and shares the LoyaltyProgram and LoyaltyAdminCap objects.
fun init_logic_shares_loyalty_objects() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        loyalty::init_for_testing(scenario.ctx());
    };

    // End Tx 0 and start Tx 1 to make the shared objects available.
    scenario.next_tx(publisher);
    {
        // Now, in Tx 1, the objects should be shared.
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Assert that the initial state is correct.
        assert_eq!(loyalty_program.user_levels().length(), 0);
        assert_eq!(loyalty_program.levels().length(), 0);
        assert_eq!(loyalty_admin_cap.owner_for_testing(), publisher);

        // Return the objects to the shared pool.
        test_scenario::return_shared(loyalty_program);
        test_scenario::return_shared(loyalty_admin_cap);
    };

    // End the scenario.
    test_scenario::end(scenario);
}
