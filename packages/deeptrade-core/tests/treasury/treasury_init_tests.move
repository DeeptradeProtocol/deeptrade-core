#[test_only]
module deeptrade_core::treasury_init_tests;

use deeptrade_core::helper::current_version;
use deeptrade_core::treasury::{Self, Treasury};
use sui::bag;
use sui::test_scenario;
use sui::vec_set;

#[test]
/// Test that the init logic correctly creates and shares the Treasury object.
fun init_logic_shares_treasury_object() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    {
        treasury::init_for_testing(test_scenario::ctx(&mut scenario));
    };

    // End Tx 0 and start Tx 1 to make the shared object available.
    test_scenario::next_tx(&mut scenario, publisher);
    {
        // Now, in Tx 1, the Treasury should be a shared object.
        let treasury = test_scenario::take_shared<Treasury>(&scenario);

        // Assert that the initial state is correct using the test-only getter functions.
        assert!(vec_set::contains(treasury::allowed_versions(&treasury), &current_version()), 1);
        assert!(vec_set::size(treasury::disabled_versions(&treasury)) == 0, 2);
        assert!(treasury.deep_reserves() == 0, 3);
        assert!(bag::is_empty(treasury::deep_reserves_coverage_fees(&treasury)), 4);
        assert!(bag::is_empty(treasury::protocol_fees(&treasury)), 5);

        // Return the Treasury object to the shared pool.
        test_scenario::return_shared(treasury);
    };

    // End the scenario.
    test_scenario::end(scenario);
}
