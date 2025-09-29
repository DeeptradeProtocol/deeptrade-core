#[test_only]
module deeptrade_core::update_loyalty_admin_cap_owner_tests;

use deeptrade_core::add_loyalty_level_tests::setup_test_environment;
use deeptrade_core::admin;
use deeptrade_core::loyalty::{Self, LoyaltyAdminCap, LoyaltyProgram, ESenderIsNotLoyaltyAdmin};
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

#[test]
fun successful_owner_update() {
    let mut scenario = setup_test_environment();
    let multisig_address = get_test_multisig_address();

    // 1. Update owner to ALICE
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::update_loyalty_admin_cap_owner(
            &mut loyalty_admin_cap,
            &config,
            &admin_cap,
            ALICE,
            scenario.ctx(),
        );

        assert_eq!(loyalty_admin_cap.owner_for_testing(), ALICE);

        destroy(admin_cap);
        return_shared(loyalty_admin_cap);
        return_shared(config);
    };

    // 2. Verify new owner (ALICE) can grant levels
    // We need to add a dummy level first to be able to grant it.
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            1,
            100_000_000,
            scenario.ctx(),
        );
        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    scenario.next_tx(ALICE);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(&mut loyalty_program, &loyalty_admin_cap, BOB, 1, scenario.ctx());

        assert_eq!(loyalty::get_user_loyalty_level(&loyalty_program, BOB).extract(), 1);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotLoyaltyAdmin)]
fun old_owner_cannot_grant_level() {
    let mut scenario = setup_test_environment();
    let multisig_address = get_test_multisig_address();

    // 1. Update owner to ALICE
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::update_loyalty_admin_cap_owner(
            &mut loyalty_admin_cap,
            &config,
            &admin_cap,
            ALICE,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_admin_cap);
        return_shared(config);
    };

    // 2. Add a dummy level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            1,
            100_000_000,
            scenario.ctx(),
        );
        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // 3. Verify old owner (OWNER) fails to grant level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(&mut loyalty_program, &loyalty_admin_cap, BOB, 1, scenario.ctx());

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun non_multisig_sender_fails() {
    let mut scenario = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::update_loyalty_admin_cap_owner(
            &mut loyalty_admin_cap,
            &config,
            &admin_cap,
            ALICE,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_admin_cap);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun update_to_same_owner() {
    let mut scenario = setup_test_environment();
    let multisig_address = get_test_multisig_address();

    scenario.next_tx(multisig_address);
    {
        let mut loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::update_loyalty_admin_cap_owner(
            &mut loyalty_admin_cap,
            &config,
            &admin_cap,
            OWNER, // Update to the same owner
            scenario.ctx(),
        );

        assert_eq!(loyalty_admin_cap.owner_for_testing(), OWNER);

        destroy(admin_cap);
        return_shared(loyalty_admin_cap);
        return_shared(config);
    };

    end(scenario);
}
