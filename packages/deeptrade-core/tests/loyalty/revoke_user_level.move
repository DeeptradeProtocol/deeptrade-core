#[test_only]
module deepbook_wrapper::revoke_user_level_tests;

use deepbook_wrapper::grant_user_level_tests::{
    setup_test_environment,
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold,
    get_test_multisig_address
};
use deepbook_wrapper::loyalty::{Self, LoyaltyProgram, EUserHasNoLoyaltyLevel, ESenderIsNotMultisig};
use std::unit_test::assert_eq;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const CHARLIE: address = @0xCCCC;

// Test loyalty levels
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;

// === Test Cases ===

#[test]
fun successful_revoke_user_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to ALICE first
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Now revoke the level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify user level was revoked
        let user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), false);

        // Verify member count decreased
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER);
        assert_eq!(member_count, 0);

        // Verify total members decreased
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun revoke_user_from_level_with_multiple_members() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant same level to multiple users
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant to all three users
        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            BOB,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            CHARLIE,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Revoke only ALICE's level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify ALICE's level was revoked
        let alice_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(alice_level_opt.is_some(), false);

        // Verify BOB and CHARLIE still have their levels
        let mut bob_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, BOB);
        let mut charlie_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, CHARLIE);
        assert_eq!(bob_level_opt.is_some(), true);
        assert_eq!(charlie_level_opt.is_some(), true);
        assert_eq!(bob_level_opt.extract(), LEVEL_GOLD);
        assert_eq!(charlie_level_opt.extract(), LEVEL_GOLD);

        // Verify member count decreased to 2
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD);
        assert_eq!(member_count, 2);

        // Verify total members decreased to 2
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 2);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun revoke_last_user_from_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to only ALICE
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_BRONZE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Revoke ALICE's level (last user in the level)
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify user level was revoked
        let user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), false);

        // Verify member count is 0
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_BRONZE);
        assert_eq!(member_count, 0);

        // Verify total members is 0
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun revoke_from_zero_address() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to zero address first
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            @0x0,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Revoke from zero address
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            @0x0,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify level was revoked
        let user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, @0x0);
        assert_eq!(user_level_opt.is_some(), false);

        // Verify member count
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER);
        assert_eq!(member_count, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EUserHasNoLoyaltyLevel)]
fun revoke_nonexistent_user_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Try to revoke a user who was never granted a level
        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotMultisig)]
fun non_multisig_sender_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level first
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Try to revoke with non-multisig sender
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun grant_then_revoke_then_regrant() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Grant level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Revoke level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Grant level again
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_GOLD,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify user has level again
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), true);
        assert_eq!(user_level_opt.extract(), LEVEL_GOLD);

        // Verify member count is 1 again
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD);
        assert_eq!(member_count, 1);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun revoke_multiple_users_same_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant same level to multiple users
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant to all three users
        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            BOB,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            CHARLIE,
            LEVEL_SILVER,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Revoke all users from the level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            BOB,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            CHARLIE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Verify all users have no level
        let alice_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        let bob_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, BOB);
        let charlie_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, CHARLIE);
        assert_eq!(alice_level_opt.is_some(), false);
        assert_eq!(bob_level_opt.is_some(), false);
        assert_eq!(charlie_level_opt.is_some(), false);

        // Verify member count is 0
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER);
        assert_eq!(member_count, 0);

        // Verify total members is 0
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    end(scenario);
}
