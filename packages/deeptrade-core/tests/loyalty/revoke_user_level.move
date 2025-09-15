#[test_only]
module deeptrade_core::revoke_user_level_tests;

use deeptrade_core::grant_user_level_tests::setup_test_environment;
use deeptrade_core::loyalty::{
    Self,
    LoyaltyAdminCap,
    LoyaltyProgram,
    EUserHasNoLoyaltyLevel,
    ESenderIsNotLoyaltyAdmin
};
use std::unit_test::assert_eq;
use sui::test_scenario::{end, return_shared};

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
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Now revoke the level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
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

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun revoke_user_from_level_with_multiple_members() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant same level to multiple users
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant to all three users
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            CHARLIE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Revoke only ALICE's level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
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

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun revoke_last_user_from_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to only ALICE
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Revoke ALICE's level (last user in the level)
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
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

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun revoke_from_zero_address() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to zero address first
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            @0x0,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Revoke from zero address
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            @0x0,
            scenario.ctx(),
        );

        // Verify level was revoked
        let user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, @0x0);
        assert_eq!(user_level_opt.is_some(), false);

        // Verify member count
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER);
        assert_eq!(member_count, 0);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EUserHasNoLoyaltyLevel)]
fun revoke_nonexistent_user_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Try to revoke a user who was never granted a level
        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotLoyaltyAdmin)]
fun revoke_level_by_non_admin_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level first
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Try to revoke with non-admin sender
    scenario.next_tx(ALICE);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun grant_then_revoke_then_regrant() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Revoke level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Grant level again
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Verify user has level again
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), true);
        assert_eq!(user_level_opt.extract(), LEVEL_GOLD);

        // Verify member count is 1 again
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD);
        assert_eq!(member_count, 1);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun revoke_multiple_users_same_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant same level to multiple users
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant to all three users
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            CHARLIE,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Revoke all users from the level
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            scenario.ctx(),
        );

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            scenario.ctx(),
        );

        loyalty::revoke_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            CHARLIE,
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

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}
