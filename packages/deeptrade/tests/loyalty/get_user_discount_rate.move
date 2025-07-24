#[test_only]
module deepbook_wrapper::get_user_discount_rate_tests;

use deepbook_wrapper::grant_user_level_tests::{
    setup_test_environment,
    get_test_multisig_pks,
    get_test_multisig_weights,
    get_test_multisig_threshold,
    get_test_multisig_address
};
use deepbook_wrapper::loyalty::{Self, LoyaltyProgram};
use std::unit_test::assert_eq;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const CHARLIE: address = @0xCCCC;
const DAVID: address = @0xDDDD;

// Test loyalty levels
const LEVEL_BRONZE: u8 = 1;
const LEVEL_SILVER: u8 = 2;
const LEVEL_GOLD: u8 = 3;
const LEVEL_PLATINUM: u8 = 4;

// Fee discount rates (in billionths)
const BRONZE_DISCOUNT: u64 = 100_000_000; // 10%
const SILVER_DISCOUNT: u64 = 250_000_000; // 25%
const GOLD_DISCOUNT: u64 = 500_000_000; // 50%
const PLATINUM_DISCOUNT: u64 = 750_000_000; // 75%

// === Test Cases ===

#[test]
fun get_discount_rate_for_user_with_no_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);

        // Test user with no loyalty level
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(discount_rate, 0);

        // Test another user with no loyalty level
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, BOB);
        assert_eq!(discount_rate, 0);

        // Test owner with no loyalty level
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, OWNER);
        assert_eq!(discount_rate, 0);

        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun get_discount_rate_for_user_with_valid_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Grant different levels to different users
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant BRONZE level to ALICE
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

        // Grant SILVER level to BOB
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

        // Grant GOLD level to CHARLIE
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

    // Test discount rates for users with different levels
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);

        // Test ALICE with BRONZE level
        let alice_discount = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(alice_discount, BRONZE_DISCOUNT);

        // Test BOB with SILVER level
        let bob_discount = loyalty::get_user_discount_rate(&loyalty_program, BOB);
        assert_eq!(bob_discount, SILVER_DISCOUNT);

        // Test CHARLIE with GOLD level
        let charlie_discount = loyalty::get_user_discount_rate(&loyalty_program, CHARLIE);
        assert_eq!(charlie_discount, GOLD_DISCOUNT);

        // Test DAVID with no level (should return 0)
        let david_discount = loyalty::get_user_discount_rate(&loyalty_program, DAVID);
        assert_eq!(david_discount, 0);

        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun get_discount_rate_after_level_changes() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Grant initial level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant BRONZE level to ALICE
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

    // Verify initial discount rate
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let initial_discount = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(initial_discount, BRONZE_DISCOUNT);
        return_shared(loyalty_program);
    };

    // Revoke the level
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

    // Verify discount rate is now 0
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let revoked_discount = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(revoked_discount, 0);
        return_shared(loyalty_program);
    };

    // Grant a different level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant GOLD level to ALICE
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

    // Verify new discount rate
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let new_discount = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(new_discount, GOLD_DISCOUNT);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun get_discount_rate_for_nonexistent_level_edge_case() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Add a new level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add a new level
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &admin_cap,
            LEVEL_PLATINUM,
            PLATINUM_DISCOUNT,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Grant the new level to ALICE
        loyalty::grant_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            LEVEL_PLATINUM,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Verify the discount rate works correctly
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(discount_rate, PLATINUM_DISCOUNT);
        return_shared(loyalty_program);
    };

    // First revoke ALICE's level, then remove the level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // First revoke ALICE's level
        loyalty::revoke_user_level(
            &mut loyalty_program,
            &admin_cap,
            ALICE,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        // Now remove the level
        loyalty::remove_loyalty_level(
            &mut loyalty_program,
            &admin_cap,
            LEVEL_PLATINUM,
            get_test_multisig_pks(),
            get_test_multisig_weights(),
            get_test_multisig_threshold(),
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
    };

    // Verify discount rate is now 0 (user has no level)
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, ALICE);
        assert_eq!(discount_rate, 0);
        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun get_discount_rate_multiple_users_same_level() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Grant same level to multiple users
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant GOLD level to multiple users
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

    // Verify all users get the same discount rate
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);

        assert_eq!(loyalty::get_user_discount_rate(&loyalty_program, ALICE), GOLD_DISCOUNT);
        assert_eq!(loyalty::get_user_discount_rate(&loyalty_program, BOB), GOLD_DISCOUNT);
        assert_eq!(loyalty::get_user_discount_rate(&loyalty_program, CHARLIE), GOLD_DISCOUNT);

        return_shared(loyalty_program);
    };

    end(scenario);
}

#[test]
fun get_discount_rate_consistency_with_view_functions() {
    let (mut scenario, loyalty_program_id) = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Grant level to user
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);
        let admin_cap = deepbook_wrapper::admin::get_admin_cap_for_testing(scenario.ctx());

        // Grant SILVER level to ALICE
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

    // Verify consistency between get_user_discount_rate and the individual view functions
    scenario.next_tx(OWNER);
    {
        let loyalty_program = scenario.take_shared_by_id<LoyaltyProgram>(loyalty_program_id);

        // Get discount rate using the main function
        let discount_rate = loyalty::get_user_discount_rate(&loyalty_program, ALICE);

        // Get the same result using individual view functions
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, ALICE);
        assert_eq!(user_level_opt.is_some(), true);
        let user_level = user_level_opt.extract();
        assert_eq!(user_level, LEVEL_SILVER);

        let mut level_discount_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            user_level,
        );
        assert_eq!(level_discount_opt.is_some(), true);
        let level_discount = level_discount_opt.extract();

        // Verify consistency
        assert_eq!(discount_rate, level_discount);
        assert_eq!(discount_rate, SILVER_DISCOUNT);

        return_shared(loyalty_program);
    };

    end(scenario);
}
