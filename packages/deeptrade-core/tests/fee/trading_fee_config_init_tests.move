#[test_only]
module deeptrade_core::trading_fee_config_init_tests;

use deeptrade_core::fee::{
    Self,
    TradingFeeConfig,
    new_pool_fee_config,
    get_fee_defaults,
    default_fees,
    pool_specific_fees
};
use sui::table;
use sui::test_scenario::{Self, Scenario};

/// Test that the init logic correctly creates and shares the TradingFeeConfig object.
#[test]
fun test_init_shares_trading_fee_config() {
    let publisher = @0xABCD;
    let mut scenario = test_scenario::begin(publisher);
    setup_with_trading_fee_config(&mut scenario, publisher);

    scenario.next_tx(publisher);
    {
        let config = scenario.take_shared<TradingFeeConfig>();
        let default_fees = default_fees(&config);

        let (deep_taker, deep_maker, input_taker, input_maker, max_discount) = get_fee_defaults();

        let expected_defaults = new_pool_fee_config(
            deep_taker,
            deep_maker,
            input_taker,
            input_maker,
            max_discount,
        );

        assert!(default_fees == expected_defaults, 1);
        assert!(table::length(pool_specific_fees(&config)) == 0, 2);

        test_scenario::return_shared(config);
    };

    scenario.end();
}

// === Helper Functions ===
/// Initializes a test scenario and the TradingFeeConfig object.
#[test_only]
public fun setup_with_trading_fee_config(scenario: &mut Scenario, sender: address) {
    scenario.next_tx(sender);
    fee::init_for_testing(scenario.ctx());
    scenario.next_tx(sender);
}
