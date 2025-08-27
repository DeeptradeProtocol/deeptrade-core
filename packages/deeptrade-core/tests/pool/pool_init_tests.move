#[test_only]
module deeptrade_core::pool_init_tests;

use deeptrade_core::pool::{
    Self,
    PoolCreationConfig,
    pool_creation_protocol_fee,
    default_pool_creation_protocol_fee
};
use sui::test_scenario;

#[test]
/// Test that the init logic correctly creates and shares the PoolCreationConfig object.
fun test_init_shares_pool_creation_config() {
    let publisher = @0xABCD;
    let mut scenario = setup_with_pool_creation_config(publisher);

    // End Tx 0 and start Tx 1 to make the shared object available.
    test_scenario::next_tx(&mut scenario, publisher);
    {
        // Now, in Tx 1, the PoolCreationConfig should be a shared object.
        let config = test_scenario::take_shared<PoolCreationConfig>(&scenario);

        // Assert that the initial state is correct.
        assert!(pool_creation_protocol_fee(&config) == default_pool_creation_protocol_fee(), 1);

        // Return the object to the shared pool.
        test_scenario::return_shared(config);
    };

    // End the scenario.
    test_scenario::end(scenario);
}

// === Helper Functions ===
/// Initializes a test scenario and the PoolCreationConfig object.
#[test_only]
public fun setup_with_pool_creation_config(sender: address): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(sender);
    {
        pool::init_for_testing(scenario.ctx());
    };

    scenario
}
