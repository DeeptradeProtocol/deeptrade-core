#[test_only]
module deeptrade_core::treasury_init_tests;

use deeptrade_core::helper::current_version;
use deeptrade_core::treasury::{Self, Treasury};
use std::unit_test::assert_eq;
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and shares the Treasury object.
fun init_logic_shares_treasury_object() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // End Tx 0 and start Tx 1 to make the shared object available.
    scenario.next_tx(publisher);
    {
        // Now, in Tx 1, the Treasury should be a shared object.
        let treasury = scenario.take_shared<Treasury>();

        // Assert that the initial state is correct using the test-only getter functions.
        assert_eq!(treasury.allowed_versions().contains(&current_version()), true);
        assert_eq!(treasury.disabled_versions().size(), 0);
        assert_eq!(treasury.deep_reserves(), 0);
        assert_eq!(treasury.deep_reserves_coverage_fees().is_empty(), true);
        assert_eq!(treasury.protocol_fees().is_empty(), true);

        // Return the Treasury object to the shared pool.
        test_scenario::return_shared(treasury);
    };

    // End the scenario.
    test_scenario::end(scenario);
}
