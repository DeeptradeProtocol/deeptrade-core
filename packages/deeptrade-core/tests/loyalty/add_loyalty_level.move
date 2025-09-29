#[test_only]
module deeptrade_core::add_loyalty_level_tests;

use deeptrade_core::loyalty::{
    Self,
    LoyaltyAdminCap,
    LoyaltyProgram,
    ELoyaltyLevelAlreadyExists,
    EInvalidFeeDiscountRate
};
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use deeptrade_core::update_multisig_config_tests::setup_with_initialized_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::test_scenario::{Scenario, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;

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
const ZERO_DISCOUNT: u64 = 0; // 0%
const MAX_DISCOUNT: u64 = 1_000_000_000; // 100%
const INVALID_DISCOUNT: u64 = 1_000_000_001; // > 100%

// === Test Cases ===

#[test]
fun successful_add_loyalty_level() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            PLATINUM_DISCOUNT,
            scenario.ctx(),
        );

        // Verify level was added correctly
        let mut discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(discount_rate_opt.is_some(), true);
        assert_eq!(discount_rate_opt.extract(), PLATINUM_DISCOUNT);

        // Verify member count is 0
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_PLATINUM);
        assert_eq!(member_count, 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun add_multiple_loyalty_levels() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add multiple levels
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

        // Verify all levels were added correctly
        let mut bronze_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_BRONZE,
        );
        let mut silver_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_SILVER,
        );
        let mut gold_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_GOLD,
        );

        assert_eq!(bronze_rate_opt.is_some(), true);
        assert_eq!(silver_rate_opt.is_some(), true);
        assert_eq!(gold_rate_opt.is_some(), true);
        assert_eq!(bronze_rate_opt.extract(), BRONZE_DISCOUNT);
        assert_eq!(silver_rate_opt.extract(), SILVER_DISCOUNT);
        assert_eq!(gold_rate_opt.extract(), GOLD_DISCOUNT);

        // Verify all have zero member count
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_BRONZE), 0);
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_SILVER), 0);
        assert_eq!(loyalty::get_level_member_count(&loyalty_program, LEVEL_GOLD), 0);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun add_level_with_max_discount_rate() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            MAX_DISCOUNT,
            scenario.ctx(),
        );

        // Verify level was added with max discount rate
        let mut discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(discount_rate_opt.is_some(), true);
        assert_eq!(discount_rate_opt.extract(), MAX_DISCOUNT);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EInvalidFeeDiscountRate)]
fun add_level_with_zero_discount_rate_fails() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Try to add level with zero discount rate (should fail)
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_BRONZE,
            ZERO_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun add_level_with_different_level_ids() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add level with ID 0
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_ZERO,
            BRONZE_DISCOUNT,
            scenario.ctx(),
        );

        // Add level with max u8 value
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_MAX,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        // Verify both levels were added correctly
        let mut zero_level_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_ZERO,
        );
        let mut max_level_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_MAX,
        );

        assert_eq!(zero_level_rate_opt.is_some(), true);
        assert_eq!(max_level_rate_opt.is_some(), true);
        assert_eq!(zero_level_rate_opt.extract(), BRONZE_DISCOUNT);
        assert_eq!(max_level_rate_opt.extract(), GOLD_DISCOUNT);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ELoyaltyLevelAlreadyExists)]
fun add_duplicate_level_fails() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Add level first time
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            SILVER_DISCOUNT,
            scenario.ctx(),
        );

        // Try to add the same level again
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_SILVER,
            GOLD_DISCOUNT, // Different discount rate, but same level ID
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EInvalidFeeDiscountRate)]
fun add_level_with_invalid_discount_rate_fails() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Try to add level with discount rate > 100%
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            INVALID_DISCOUNT,
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
    let mut scenario = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        // Use invalid multisig parameters to trigger failure
        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_GOLD,
            GOLD_DISCOUNT,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun add_then_remove_then_add_again() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Add level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

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

    // Remove level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
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

    // Add level again
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        loyalty::add_loyalty_level(
            &mut loyalty_program,
            &config,
            &admin_cap,
            LEVEL_PLATINUM,
            GOLD_DISCOUNT, // Different discount rate this time
            scenario.ctx(),
        );

        // Verify level was added again
        let mut discount_rate_opt = loyalty::get_loyalty_level_fee_discount_rate(
            &loyalty_program,
            LEVEL_PLATINUM,
        );
        assert_eq!(discount_rate_opt.is_some(), true);
        assert_eq!(discount_rate_opt.extract(), GOLD_DISCOUNT);

        destroy(admin_cap);
        return_shared(loyalty_program);
        return_shared(config);
    };

    end(scenario);
}

#[test]
fun add_level_then_grant_to_user() {
    let mut scenario = setup_test_environment();

    let multisig_address = get_test_multisig_address();

    // Add new level
    scenario.next_tx(multisig_address);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

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

    // Grant the new level to a user
    scenario.next_tx(OWNER);
    {
        let mut loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let loyalty_admin_cap = scenario.take_shared<LoyaltyAdminCap>();

        loyalty::grant_user_level(
            &mut loyalty_program,
            &loyalty_admin_cap,
            @0xAAAA,
            LEVEL_PLATINUM,
            scenario.ctx(),
        );

        // Verify user has the new level
        let mut user_level_opt = loyalty::get_user_loyalty_level(&loyalty_program, @0xAAAA);
        assert_eq!(user_level_opt.is_some(), true);
        assert_eq!(user_level_opt.extract(), LEVEL_PLATINUM);

        // Verify member count increased
        let member_count = loyalty::get_level_member_count(&loyalty_program, LEVEL_PLATINUM);
        assert_eq!(member_count, 1);

        return_shared(loyalty_program);
        return_shared(loyalty_admin_cap);
    };

    end(scenario);
}

// === Helper Functions ===

/// Sets up a test environment with loyalty program but without pre-added levels.
/// Returns (scenario) ready for testing.
#[test_only]
public(package) fun setup_test_environment(): Scenario {
    let mut scenario = setup_with_initialized_config();

    // Initialize loyalty program
    scenario.next_tx(OWNER);
    {
        loyalty::init_for_testing(scenario.ctx());
    };

    scenario
}
