#[test_only]
module deeptrade_core::create_rebates_claimer_cap_tests;

use deeptrade_core::admin;
use deeptrade_core::fee_manager::{Self, RebatesClaimerCap};
use deeptrade_core::initialize_multisig_config_tests::setup;
use deeptrade_core::multisig_config::{MultisigConfig, EMultisigConfigNotInitialized, ESenderIsNotValidMultisig};
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{Self, Scenario, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

#[test]
fun successful_create() {
    let mut scenario = setup_with_initialized_config();
    let multisig_address = get_test_multisig_address();

    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::create_rebates_claimer_cap(&config, &admin_cap, ALICE, scenario.ctx());

        destroy(admin_cap);
        return_shared(config);
    };

    scenario.next_tx(ALICE);
    {
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();
        assert_eq!(rebates_claimer_cap.owner_for_testing(), ALICE);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test]
fun create_more_than_once() {
    let mut scenario = setup_with_initialized_config();

    create_rebates_claimer_cap_as_admin(&mut scenario, ALICE);
    scenario.next_tx(ALICE);
    let alice_cap_id = test_scenario::most_recent_id_shared<RebatesClaimerCap>().extract();

    create_rebates_claimer_cap_as_admin(&mut scenario, BOB);
    scenario.next_tx(BOB);
    let bob_cap_id = test_scenario::most_recent_id_shared<RebatesClaimerCap>().extract();

    scenario.next_tx(OWNER);
    {
        let alice_cap = scenario.take_shared_by_id<RebatesClaimerCap>(alice_cap_id);
        let bob_cap = scenario.take_shared_by_id<RebatesClaimerCap>(bob_cap_id);

        assert_eq!(alice_cap.owner_for_testing(), ALICE);
        assert_eq!(bob_cap.owner_for_testing(), BOB);

        return_shared(alice_cap);
        return_shared(bob_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun non_multisig_sender_fails() {
    let mut scenario = setup_with_initialized_config();

    scenario.next_tx(OWNER);
    {
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::create_rebates_claimer_cap(&config, &admin_cap, ALICE, scenario.ctx());

        destroy(admin_cap);
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
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::create_rebates_claimer_cap(&config, &admin_cap, ALICE, scenario.ctx());

        destroy(admin_cap);
        return_shared(config);
    };

    end(scenario);
}

/// Creates a `RebatesClaimerCap` as the admin multisig and assigns it to `owner`.
#[test_only]
public(package) fun create_rebates_claimer_cap_as_admin(scenario: &mut Scenario, owner: address) {
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        fee_manager::create_rebates_claimer_cap(&config, &admin_cap, owner, scenario.ctx());

        destroy(admin_cap);
        return_shared(config);
    };
}
