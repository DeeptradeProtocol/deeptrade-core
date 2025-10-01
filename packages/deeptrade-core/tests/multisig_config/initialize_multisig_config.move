#[test_only]
module deeptrade_core::initialize_multisig_config_tests;

use deeptrade_core::multisig_config::{
    Self,
    MultisigConfig,
    MultisigConfigInitialized,
    EMultisigConfigAlreadyInitialized,
    ETooFewSigners
};
use multisig::multisig::{
    Self,
    ELengthsOfPksAndWeightsAreNotEqual,
    EThresholdIsPositiveAndNotGreaterThanTheSumOfWeights
};
use multisig::multisig_test_utils::{
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold,
    get_test_multisig_address
};
use std::unit_test::assert_eq;
use sui::event;
use sui::test_scenario::{Self, Scenario, end, return_shared};
use sui::test_utils;

const OWNER: address = @0x1;

// === Tests ===

#[test]
fun success() {
    let mut scenario = setup();

    let pks = get_test_multisig_pks();
    let weights = get_test_multisig_weights();
    let threshold = get_test_multisig_threshold();
    let multisig_address = get_test_multisig_address();

    let config_id;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());
        config_id = object::id(&config);

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        let (
            updated_pks,
            updated_weights,
            updated_threshold,
        ) = multisig_config::get_multisig_config_params(&config);

        let new_address_derived = multisig::derive_multisig_address_quiet(
            updated_pks,
            updated_weights,
            updated_threshold,
        );

        assert_eq!(updated_pks, pks);
        assert_eq!(updated_weights, weights);
        assert_eq!(updated_threshold, threshold);
        assert_eq!(new_address_derived, multisig_address);

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    let events = event::events_by_type<MultisigConfigInitialized>();
    assert_eq!(events.length(), 1);
    let event = events[0];

    let (
        event_config_id,
        event_pks,
        event_weights,
        event_threshold,
        event_address,
    ) = multisig_config::unwrap_multisig_config_initialized_event(&event);

    assert_eq!(config_id, event_config_id);
    assert_eq!(pks, event_pks);
    assert_eq!(weights, event_weights);
    assert_eq!(threshold, event_threshold);
    assert_eq!(multisig_address, event_address);

    end(scenario);
}

#[test, expected_failure(abort_code = EMultisigConfigAlreadyInitialized)]
fun already_initialized_fails() {
    let mut scenario = setup();

    let pks = get_test_multisig_pks();
    let weights = get_test_multisig_weights();
    let threshold = get_test_multisig_threshold();

    // First call, successful initialization
    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    // Second call, should fail
    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ELengthsOfPksAndWeightsAreNotEqual)]
fun mismatched_pks_and_weights_fails() {
    let mut scenario = setup();

    let pks = get_test_multisig_pks();
    let mut weights = get_test_multisig_weights();
    let threshold = get_test_multisig_threshold();

    // Remove one weight to create a mismatch
    weights.pop_back();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EThresholdIsPositiveAndNotGreaterThanTheSumOfWeights)]
fun zero_threshold_fails() {
    let mut scenario = setup();

    let pks = get_test_multisig_pks();
    let weights = get_test_multisig_weights();
    let threshold = 0;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EThresholdIsPositiveAndNotGreaterThanTheSumOfWeights)]
fun unachievable_threshold_fails() {
    let mut scenario = setup();

    let pks = get_test_multisig_pks();
    let weights = get_test_multisig_weights();
    // Sum of weights is 3, so 4 is unachievable
    let threshold = 4;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ETooFewSigners)]
fun too_few_signers_fails() {
    let mut scenario = setup();

    let mut pks = get_test_multisig_pks();
    let mut weights = get_test_multisig_weights();
    // With one signer, threshold must be 1
    let threshold = 1;

    // Remove two signers to have only one
    pks.pop_back();
    pks.pop_back();
    weights.pop_back();
    weights.pop_back();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            pks,
            weights,
            threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

// === Helpers ===

#[test_only]
public(package) fun setup(): Scenario {
    let mut scenario = test_scenario::begin(OWNER);

    scenario.next_tx(OWNER);
    {
        multisig_config::init_for_testing(scenario.ctx());
    };

    scenario
}
