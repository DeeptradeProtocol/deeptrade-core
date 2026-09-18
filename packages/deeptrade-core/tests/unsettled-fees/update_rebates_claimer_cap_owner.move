#[test_only]
module deeptrade_core::update_rebates_claimer_cap_owner_tests;

use deeptrade_core::admin;
use deeptrade_core::create_rebates_claimer_cap_tests::create_rebates_claimer_cap_as_admin;
use deeptrade_core::fee_manager::{Self, RebatesClaimerCap};
use deeptrade_core::initialize_multisig_config_tests::setup;
use deeptrade_core::multisig_config::{MultisigConfig, EMultisigConfigNotInitialized, ESenderIsNotValidMultisig};
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{Scenario, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

#[test]
fun successful_owner_update() {
    let mut scenario = setup_with_initialized_config();
    let multisig_address = get_test_multisig_address();

    create_rebates_claimer_cap_as_admin(&mut scenario, ALICE);

    scenario.next_tx(multisig_address);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            BOB,
            scenario.ctx(),
        );

        assert_eq!(rebates_claimer_cap.owner_for_testing(), BOB);

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun non_multisig_sender_fails() {
    let mut scenario = setup_with_initialized_config();

    create_rebates_claimer_cap_as_admin(&mut scenario, ALICE);

    scenario.next_tx(OWNER);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            BOB,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun update_to_same_owner() {
    let mut scenario = setup_with_initialized_config();
    let multisig_address = get_test_multisig_address();

    create_rebates_claimer_cap_as_admin(&mut scenario, ALICE);

    scenario.next_tx(multisig_address);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            ALICE,
            scenario.ctx(),
        );

        assert_eq!(rebates_claimer_cap.owner_for_testing(), ALICE);

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun cap_owner_cannot_update_owner() {
    let mut scenario = setup_with_initialized_config();

    create_rebates_claimer_cap_as_admin(&mut scenario, ALICE);

    scenario.next_tx(ALICE);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            BOB,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EMultisigConfigNotInitialized)]
fun uninitialized_config_fails() {
    let mut scenario = setup();
    let multisig_address = get_test_multisig_address();

    scenario.next_tx(multisig_address);
    {
        fee_manager::share_rebates_claimer_cap_for_testing(ALICE, scenario.ctx());
    };

    scenario.next_tx(multisig_address);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            BOB,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };

    end(scenario);
}

/// Updates the owner of the shared `RebatesClaimerCap` as the admin multisig.
#[test_only]
public(package) fun update_rebates_claimer_cap_owner_as_admin(
    scenario: &mut Scenario,
    new_owner: address,
) {
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::update_rebates_claimer_cap_owner(
            &mut rebates_claimer_cap,
            &config,
            &admin_cap,
            new_owner,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(rebates_claimer_cap);
        return_shared(config);
    };
}
