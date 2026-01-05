#[test_only]
module deeptrade_core::pool_init_tests;

use deeptrade_core::dt_pool::{
    Self as pool,
    PoolCreationConfig,
    pool_creation_protocol_fee,
    default_pool_creation_protocol_fee
};
use sui::test_scenario::{Self, Scenario};

/// Test that the init logic correctly creates and shares the PoolCreationConfig object.
#[test]
fun test_init_shares_pool_creation_config() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    setup_with_pool_creation_config(&mut scenario, publisher);

    // End Tx 0 and start Tx 1 to make the shared object available.
    scenario.next_tx(publisher);
    {
        // Now, in Tx 1, the PoolCreationConfig should be a shared object.
        let config = test_scenario::take_shared<PoolCreationConfig>(&scenario);

        // Assert that the initial state is correct.
        assert!(pool_creation_protocol_fee(&config) == default_pool_creation_protocol_fee(), 1);

        // Return the object to the shared pool.
        test_scenario::return_shared(config);
    };

    // End the scenario.
    scenario.end();
}

// === Helper Functions ===
/// Initializes a test scenario and the PoolCreationConfig object.
#[test_only]
public fun setup_with_pool_creation_config(scenario: &mut Scenario, sender: address) {
    scenario.next_tx(sender);
    pool::init_for_testing(scenario.ctx());
    scenario.next_tx(sender);
}
