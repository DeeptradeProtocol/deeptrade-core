#[test_only]
module deeptrade_core::loyalty_init_tests;

use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use sui::table;
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and shares the LoyaltyProgram object.
fun init_logic_shares_loyalty_program_object() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        loyalty::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    // End Tx 0 and start Tx 1 to make the shared object available.
    test_scenario::next_tx(&mut scenario, publisher);
    {
        // Now, in Tx 1, the LoyaltyProgram should be a shared object.
        let loyalty_program = test_scenario::take_shared<LoyaltyProgram>(&scenario);

        // Assert that the initial state is correct using the test-only getter functions.
        assert!(table::length(loyalty::user_levels(&loyalty_program)) == 0, 1);
        assert!(table::length(loyalty::levels(&loyalty_program)) == 0, 2);

        // Return the LoyaltyProgram object to the shared pool.
        test_scenario::return_shared(loyalty_program);
    };

    // End the scenario.
    test_scenario::end(scenario);
}
