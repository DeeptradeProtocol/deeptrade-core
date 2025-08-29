#[test_only]
module deeptrade_core::loyalty_init_tests;

use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use std::unit_test::assert_eq;
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and shares the LoyaltyProgram object.
fun init_logic_shares_loyalty_program_object() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        loyalty::init_for_testing(scenario.ctx());
    };

    // End Tx 0 and start Tx 1 to make the shared object available.
    scenario.next_tx(publisher);
    {
        // Now, in Tx 1, the LoyaltyProgram should be a shared object.
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();

        // Assert that the initial state is correct using the test-only getter functions.
        assert_eq!(loyalty_program.user_levels().length(), 0);
        assert_eq!(loyalty_program.levels().length(), 0);

        // Return the LoyaltyProgram object to the shared pool.
        test_scenario::return_shared(loyalty_program);
    };

    // End the scenario.
    test_scenario::end(scenario);
}
