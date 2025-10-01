#[test_only]
module deeptrade_core::remove_loyalty_level_tests;

use deeptrade_core::grant_user_level_tests::setup_test_environment;
use deeptrade_core::loyalty::{
    Self,
    LoyaltyAdminCap,
    LoyaltyProgram,
    ELoyaltyLevelNotFound,
    ELoyaltyLevelHasUsers
};
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

// Test loyalty levels
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;
const LEVEL_PLATINUM: u8 = 4;
const LEVEL_ZERO: u8 = 0;
const LEVEL_MAX: u8 = 255;

// Fee discount rates (in billionths)
const BRONZE_DISCOUNT: u64 = 100_000_000; // 10%
const SILVER_DISCOUNT: u64 = 250_000_000; // 25%
const GOLD_DISCOUNT: u64 = 500_000_000; // 50%
const PLATINUM_DISCOUNT: u64 = 750_000_000; // 75%

// === Test Cases ===

#[test]
fun successful_remove_loyalty_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add a new level first
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            PLATINUM_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Now remove the level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            scenario.ctx(),
        );

        // Verify level was removed
        let discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(discount_rate_opt.is_some(), false);

        // Verify member count is 0 (level doesn't exist)
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_PLATINUM);
        assert_eq!(member_count, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun remove_multiple_empty_levels() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add multiple new levels
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            PLATINUM_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            10u8,
            SILVER_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            20u8,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Remove all the new levels
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            scenario.ctx(),
        );

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            10u8,
            scenario.ctx(),
        );

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            20u8,
            scenario.ctx(),
        );

        // Verify all levels were removed
        let platinum_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        let level10_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(&loyalty_program, 10u8);
        let level20_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(&loyalty_program, 20u8);

        assert_eq!(platinum_rate_opt.is_some(), false);
        assert_eq!(level10_rate_opt.is_some(), false);
        assert_eq!(level20_rate_opt.is_some(), false);

        // Verify original levels still exist
        let bronze_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_BRONZE,
        );
        let silver_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_SILVER,
        );
        let gold_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_GOLD,
        );

        assert_eq!(bronze_rate_opt.is_some(), true);
        assert_eq!(silver_rate_opt.is_some(), true);
        assert_eq!(gold_rate_opt.is_some(), true);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun remove_level_with_different_ids() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add levels with different IDs
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_ZERO,
            BRONZE_DISCOUNT,
            scenario.ctx(),
        );

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_MAX,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Remove the levels
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_ZERO,
            scenario.ctx(),
        );

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_MAX,
            scenario.ctx(),
        );

        // Verify levels were removed
        let zero_level_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_ZERO,
        );
        let max_level_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_MAX,
        );

        assert_eq!(zero_level_rate_opt.is_some(), false);
        assert_eq!(max_level_rate_opt.is_some(), false);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ELoyaltyLevelNotFound)]
fun remove_nonexistent_level_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Try to remove a level that doesn't exist
        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            99u8, // Non-existent level
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ELoyaltyLevelHasUsers)]
fun remove_level_with_members_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant a level to a user (this creates a member)
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

    // Try to remove the level that has a member
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun non_multisig_sender_fails() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Use invalid multisig parameters to trigger failure
        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun remove_level_after_revoking_all_users() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    // Grant level to multiple users
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        // Grant to multiple users
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
            LEVEL_BRONZE,
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

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    // Now remove the level (should succeed since no members)
    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        // Verify level was removed
        let discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_BRONZE,
        );
        assert_eq!(discount_rate_opt.is_some(), false);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun remove_last_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Remove all existing levels
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Remove all levels (they start with 0 members)
        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            scenario.ctx(),
        );

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            scenario.ctx(),
        );

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_GOLD,
            scenario.ctx(),
        );

        // Verify all levels were removed
        let bronze_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_BRONZE,
        );
        let silver_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_SILVER,
        );
        let gold_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_GOLD,
        );

        assert_eq!(bronze_rate_opt.is_some(), false);
        assert_eq!(silver_rate_opt.is_some(), false);
        assert_eq!(gold_rate_opt.is_some(), false);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun remove_level_then_verify_state() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add a new level
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            PLATINUM_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Remove the level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    // Verify level is completely removed and can't be accessed
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Verify level doesn't exist
        let discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(discount_rate_opt.is_some(), false);

        // Verify member count is 0
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_PLATINUM);
        assert_eq!(member_count, 0);

        // Verify we can add the same level again (proving it was completely removed)
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            GOLD_DISCOUNT, // Different discount rate
            scenario.ctx(),
        );

        // Verify the new level exists
        let mut new_discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(new_discount_rate_opt.is_some(), true);
        assert_eq!(new_discount_rate_opt.extract(), GOLD_DISCOUNT);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}
