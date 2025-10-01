#[test_only]
module deeptrade_core::update_multisig_config_tests;

use deeptrade_core::initialize_multisig_config_tests::setup;
use deeptrade_core::multisig_config::{
    Self,
    MultisigConfig,
    MultisigConfigUpdated,
    ENewAddressIsOldAddress,
    EMultisigConfigNotInitialized,
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
use sui::test_scenario::{Scenario, return_shared, end};
use sui::test_utils;

const OWNER: address = @0x1;

// === Tests ===

#[test]
fun success() {
    let mut scenario = setup_with_initialized_config();

    let old_pks = get_test_multisig_pks();
    let old_weights = get_test_multisig_weights();
    let old_threshold = get_test_multisig_threshold();
    let old_address = get_test_multisig_address();

    // Create a new valid config
    let new_pks = vector[b"pk1_new", b"pk2_new", b"pk3_new"];
    let new_weights = vector[1, 1, 1];
    let new_threshold = 2;
    let new_address = multisig::derive_multisig_address_quiet(
        new_pks,
        new_weights,
        new_threshold,
    );
    let config_id: ID;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        config_id = object::id(&config);
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
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

        assert_eq!(updated_pks, new_pks);
        assert_eq!(updated_weights, new_weights);
        assert_eq!(updated_threshold, new_threshold);
        assert_eq!(new_address_derived, new_address);

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    let events = event::events_by_type<MultisigConfigUpdated>();
    assert_eq!(events.length(), 1);
    let event = events[0];

    let (
        event_config_id,
        event_old_pks,
        event_new_pks,
        event_old_weights,
        event_new_weights,
        event_old_threshold,
        event_new_threshold,
        event_old_address,
        event_new_address,
    ) = multisig_config::unwrap_multisig_config_updated_event(&event);

    assert_eq!(config_id, event_config_id);
    assert_eq!(old_pks, event_old_pks);
    assert_eq!(new_pks, event_new_pks);
    assert_eq!(old_weights, event_old_weights);
    assert_eq!(new_weights, event_new_weights);
    assert_eq!(old_threshold, event_old_threshold);
    assert_eq!(new_threshold, event_new_threshold);
    assert_eq!(old_address, event_old_address);
    assert_eq!(new_address, event_new_address);

    end(scenario);
}

#[test, expected_failure(abort_code = EMultisigConfigNotInitialized)]
fun not_initialized_fails() {
    let mut scenario = setup();

    let new_pks = get_test_multisig_pks();
    let new_weights = get_test_multisig_weights();
    let new_threshold = get_test_multisig_threshold();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ENewAddressIsOldAddress)]
fun new_address_is_old_address_fails() {
    let mut scenario = setup_with_initialized_config();

    // Attempt to update with the same parameters used for initialization
    let pks = get_test_multisig_pks();
    let weights = get_test_multisig_weights();
    let threshold = get_test_multisig_threshold();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
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
    let mut scenario = setup_with_initialized_config();

    let new_pks = get_test_multisig_pks();
    let mut new_weights = get_test_multisig_weights();
    let new_threshold = get_test_multisig_threshold();

    // Create a mismatch
    new_weights.pop_back();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EThresholdIsPositiveAndNotGreaterThanTheSumOfWeights)]
fun zero_threshold_fails() {
    let mut scenario = setup_with_initialized_config();

    let new_pks = get_test_multisig_pks();
    let new_weights = get_test_multisig_weights();
    let new_threshold = 0;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EThresholdIsPositiveAndNotGreaterThanTheSumOfWeights)]
fun unachievable_threshold_fails() {
    let mut scenario = setup_with_initialized_config();

    let new_pks = get_test_multisig_pks();
    let new_weights = get_test_multisig_weights();
    // Sum of weights is 3, so 4 is unachievable
    let new_threshold = 4;

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ETooFewSigners)]
fun too_few_signers_fails() {
    let mut scenario = setup_with_initialized_config();

    let mut new_pks = get_test_multisig_pks();
    let mut new_weights = get_test_multisig_weights();
    // With one signer, threshold must be 1
    let new_threshold = 1;

    // Remove two signers to have only one
    new_pks.pop_back();
    new_pks.pop_back();
    new_weights.pop_back();
    new_weights.pop_back();

    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::update_multisig_config(
            &mut config,
            &admin_cap,
            new_pks,
            new_weights,
            new_threshold,
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

// === Helpers ===
#[test_only]
public(package) fun setup_with_initialized_config(): Scenario {
    let mut scenario = setup();

    // Initialize it
    scenario.next_tx(OWNER);
    {
        let mut config = scenario.take_shared<MultisigConfig>();
        let admin_cap = multisig_config::get_multisig_admin_cap_for_testing(scenario.ctx());

        multisig_config::initialize_multisig_config(
            &mut config,
            &admin_cap,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
        );

        test_utils::destroy(admin_cap);
        return_shared(config);
    };

    scenario
}
