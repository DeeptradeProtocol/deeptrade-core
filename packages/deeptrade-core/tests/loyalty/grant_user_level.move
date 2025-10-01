#[test_only]
module deeptrade_core::grant_user_level_tests;

use deeptrade_core::initialize_multisig_config_tests::setup;
use deeptrade_core::loyalty::{
    Self,
    LoyaltyProgram,
    LoyaltyAdminCap,
    ELoyaltyLevelNotFound,
    EUserAlreadyHasLoyaltyLevel,
    ESenderIsNotLoyaltyAdmin
};
use deeptrade_core::multisig_config::{MultisigConfig, EMultisigConfigNotInitialized};
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{Scenario, end, return_shared};
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

// Fee discount rates (in billionths)
const BRONZE_DISCOUNT: u64 = 100_000_000; // 10%
const SILVER_DISCOUNT: u64 = 250_000_000; // 25%
const GOLD_DISCOUNT: u64 = 500_000_000; // 50%

// === Test Cases ===

#[test]
fun successful_grant_user_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to ALICE
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

        // Verify user level was granted
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), true);
        let user_level = user_level_opt.extract();
        assert_eq!(user_level, LEVEL_SILVER);

        // Verify member count increased
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER);
        assert_eq!(member_count, 1);

        // Verify total members increased
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 1);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun grant_multiple_users_same_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant same level to multiple users
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant to ALICE
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Grant to BOB
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Grant to CHARLIE
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            CHARLIE,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Verify all users have the level
        let mut alice_level = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        let mut bob_level = loyalty::get_user_loyalty_level(&loyalty_program, BOB);
        let mut charlie_level = loyalty::get_user_loyalty_level(&loyalty_program, CHARLIE);

        assert_eq!(alice_level.is_some(), true);
        assert_eq!(bob_level.is_some(), true);
        assert_eq!(charlie_level.is_some(), true);
        assert_eq!(alice_level.extract(), LEVEL_GOLD);
        assert_eq!(bob_level.extract(), LEVEL_GOLD);
        assert_eq!(charlie_level.extract(), LEVEL_GOLD);

        // Verify member count is 3
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD);
        assert_eq!(member_count, 3);

        // Verify total members is 3
        let total_members = loyalty::total_loyalty_program_members(&loyalty_program);
        assert_eq!(total_members, 3);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun grant_users_different_levels() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant different levels to different users
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_BRONZE,
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
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Verify each user has correct level
        let mut alice_level = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        let mut bob_level = loyalty::get_user_loyalty_level(&loyalty_program, BOB);
        let mut charlie_level = loyalty::get_user_loyalty_level(&loyalty_program, CHARLIE);

        assert_eq!(alice_level.is_some(), true);
        assert_eq!(bob_level.is_some(), true);
        assert_eq!(charlie_level.is_some(), true);
        assert_eq!(alice_level.extract(), LEVEL_BRONZE);
        assert_eq!(bob_level.extract(), LEVEL_SILVER);
        assert_eq!(charlie_level.extract(), LEVEL_GOLD);

        // Verify member counts for each level
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_BRONZE), 1);
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER), 1);
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD), 1);

        // Verify total members
        assert_eq!(loyalty::total_loyalty_program_members(&loyalty_program), 3);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ELoyaltyLevelNotFound)]
fun grant_nonexistent_level_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Try to grant a level that doesn't exist
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            99, // Non-existent level
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EUserAlreadyHasLoyaltyLevel)]
fun grant_level_to_user_with_existing_level_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant initial level
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            ALICE,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        // Try to grant another level to the same user
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

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotLoyaltyAdmin)]
fun grant_level_by_non_admin_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(ALICE);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            BOB,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test]
fun grant_to_zero_address_succeeds() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant level to zero address (edge case)
        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            @0x0,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        // Verify level was granted
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, @0x0);
        assert_eq!(user_level_opt.is_some(), true);
        assert_eq!(user_level_opt.extract(), LEVEL_BRONZE);

        // Verify member count
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_BRONZE), 1);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EMultisigConfigNotInitialized)]
fun add_loyalty_level_fails_uninitialized_config() {
    let mut scenario = setup();
    let multisig_address = get_test_multisig_address();

    // Initialize loyalty program
    scenario.next_tx(OWNER);
    {
        loyalty::init_for_testing(scenario.ctx());
    };

    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // This should fail because the config is not initialized
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            BRONZE_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a complete test environment with loyalty program.
/// Returns (scenario, loyalty_program_id) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): (Scenario, ID) {
    let mut scenario = setup_with_initialized_config();

    // Initialize loyalty program
    scenario.next_tx(OWNER);
    {
        loyalty::init_for_testing(scenario.ctx());
    };

    // Add loyalty levels
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    let loyalty_program_id = {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add test loyalty levels
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            BRONZE_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            SILVER_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_GOLD,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        let loyalty_program_id = object::id(&loyalty_program);
        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
        loyalty_program_id
    };

    (scenario, loyalty_program_id)
}
