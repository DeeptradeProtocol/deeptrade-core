#[test_only]
module deeptrade_core::get_deep_plan_tests;

use deeptrade_core::dt_order::{get_deep_plan, assert_deep_plan_eq};

// -------------------------------------
// Constants for realistic DEEP amounts
// -------------------------------------
const DEEP_SMALL: u64 = 1_000_000; // 1 DEEP
const DEEP_MEDIUM: u64 = 100_000_000; // 100 DEEP
const DEEP_LARGE: u64 = 10_000_000_000; // 10,000 DEEP
const DEEP_HUGE: u64 = 1_000_000_000_000; // 1,000,000 DEEP

// -------------------------------------
// Test Category 1: Whitelisted Pools
// -------------------------------------

#[test]
fun whitelisted_pools() {
    // Test 1: Whitelisted pool with zero requirements
    let plan = get_deep_plan(
        true, // is whitelisted
        0, // deep required
        0, // manager balance
        0, // wallet balance
        0, // treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, true);

    // Test 2: Whitelisted pool with non-zero requirements (should still return zeros)
    let plan = get_deep_plan(
        true, // is whitelisted
        DEEP_LARGE, // deep required
        0, // manager balance
        0, // wallet balance
        0, // treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, true);

    // Test 3: Whitelisted pool with available DEEP (should ignore available DEEP)
    let plan = get_deep_plan(
        true, // is whitelisted
        DEEP_LARGE, // deep required
        DEEP_SMALL, // some in manager
        DEEP_SMALL, // some in wallet
        DEEP_HUGE, // large treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, true);
}

// -------------------------------------
// Test Category 2: User Has Sufficient DEEP
// -------------------------------------

#[test]
fun user_has_sufficient_deep_all_in_manager() {
    // All DEEP in manager, nothing in wallet
    let required = DEEP_MEDIUM;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required, // exact amount in manager
        0, // nothing in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, 0, required, 0, true);

    // Excess DEEP in manager
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required * 2, // excess in manager
        0, // nothing in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, 0, required, 0, true);
}

#[test]
fun user_has_sufficient_deep_all_in_wallet() {
    // All DEEP in wallet, nothing in manager
    let required = DEEP_MEDIUM;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        required, // exact amount in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, required, 0, 0, true);

    // Excess DEEP in wallet
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        required * 2, // excess in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, required, 0, 0, true);
}

#[test]
fun user_has_sufficient_deep_split() {
    // DEEP split between manager and wallet
    let required = DEEP_MEDIUM;
    let manager_amount = required / 3;
    let wallet_amount = required - manager_amount;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        manager_amount, // some in manager
        wallet_amount, // rest in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, wallet_amount, manager_amount, 0, true);

    // DEEP split with excess in both
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        manager_amount * 2, // excess in manager
        wallet_amount * 2, // excess in wallet
        0, // treasury reserves (unused)
    );
    // Should only take what's needed from wallet
    assert_deep_plan_eq(plan, required - (manager_amount * 2), manager_amount * 2, 0, true);
}

#[test]
fun user_has_more_deep_in_manager_than_required() {
    // Manager has more DEEP than required
    let required = DEEP_MEDIUM;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required * 2, // double required in manager
        DEEP_SMALL, // small amount in wallet
        0, // treasury reserves (unused)
    );
    assert_deep_plan_eq(plan, 0, required, 0, true);
}

// -------------------------------------
// Test Category 3: User Needs Treasury DEEP
// -------------------------------------

#[test]
fun user_needs_partial_treasury_deep() {
    // User has some DEEP, needs treasury for the rest
    let required = DEEP_MEDIUM;
    let user_deep = required / 2;
    let treasury_needed = required - user_deep;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_deep, // some in wallet
        required, // sufficient treasury reserves
    );
    assert_deep_plan_eq(plan, user_deep, 0, treasury_needed, true);

    // Split user DEEP between manager and wallet
    let manager_deep = user_deep / 2;
    let wallet_deep = user_deep - manager_deep;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        manager_deep, // some in manager
        wallet_deep, // some in wallet
        required, // sufficient treasury reserves
    );
    assert_deep_plan_eq(plan, wallet_deep, manager_deep, treasury_needed, true);
}

#[test]
fun user_needs_all_treasury_deep() {
    // No user DEEP, all from treasury
    let required = DEEP_MEDIUM;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        0, // nothing in wallet
        required, // exact treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, required, true);

    // No user DEEP, treasury has excess
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        0, // nothing in wallet
        required * 2, // excess treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, required, true);
}

#[test]
fun treasury_exact_remainder() {
    // Treasury has exact amount needed for remainder
    let required = DEEP_MEDIUM;
    let user_deep = required / 3;
    let treasury_needed = required - user_deep;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_deep, // some in wallet
        treasury_needed, // exact treasury reserves needed
    );
    assert_deep_plan_eq(plan, user_deep, 0, treasury_needed, true);
}

// -------------------------------------
// Test Category 4: Insufficient Resources
// -------------------------------------

#[test]
fun insufficient_treasury_reserves() {
    // Treasury doesn't have enough to fulfill
    let required = DEEP_MEDIUM;
    let user_deep = required / 2;
    let treasury_needed = required - user_deep;
    let insufficient_reserves = treasury_needed - 1; // One token short

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_deep, // some in wallet
        insufficient_reserves, // insufficient treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);

    // Almost nothing in treasury
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_deep, // some in wallet
        1, // just 1 token in treasury
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);
}

#[test]
fun no_deep_anywhere() {
    // No DEEP anywhere, but some required
    let required = DEEP_MEDIUM;

    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        0, // nothing in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);

    // Small amount in user, none in treasury
    let small_amount = required / 10;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        small_amount, // small amount in manager
        0, // nothing in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);
}

// -------------------------------------
// Test Category 5: Edge Cases
// -------------------------------------

#[test]
fun zero_deep_required() {
    // Zero DEEP required (non-whitelisted)
    let plan = get_deep_plan(
        false, // not whitelisted
        0, // zero deep required
        0, // manager balance
        0, // wallet balance
        0, // treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, true);

    // Zero DEEP required but DEEP available
    let plan = get_deep_plan(
        false, // not whitelisted
        0, // zero deep required
        DEEP_SMALL, // some in manager
        DEEP_SMALL, // some in wallet
        DEEP_SMALL, // some in treasury
    );
    assert_deep_plan_eq(plan, 0, 0, 0, true);
}

#[test]
fun large_values() {
    // Large values (near u64 limits)
    let large_value = 9_223_372_036_854_775_000; // Just under u64::MAX

    // Large requirement with matching manager balance
    let plan = get_deep_plan(
        false, // not whitelisted
        large_value, // large deep required
        large_value, // matching manager balance
        0, // wallet balance
        0, // treasury reserves
    );
    assert_deep_plan_eq(plan, 0, large_value, 0, true);

    // Large requirement with matching wallet balance
    let plan = get_deep_plan(
        false, // not whitelisted
        large_value, // large deep required
        0, // manager balance
        large_value, // matching wallet balance
        0, // treasury reserves
    );
    assert_deep_plan_eq(plan, large_value, 0, 0, true);

    // Large requirement with matching treasury reserves
    let plan = get_deep_plan(
        false, // not whitelisted
        large_value, // large deep required
        0, // manager balance
        0, // wallet balance
        large_value, // matching treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, large_value, true);
}

// -------------------------------------
// Test Category 6: Boundary Conditions
// -------------------------------------

#[test]
fun exact_balance_boundaries() {
    // Test all combinations of exact required amounts
    let required = DEEP_MEDIUM;

    // Manager exactly matches required
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required, // exact amount in manager
        0, // nothing in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, 0, required, 0, true);

    // Wallet exactly matches required
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        required, // exact amount in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, required, 0, 0, true);

    // Combined user balance equals exactly required
    let manager_amount = required / 2;
    let wallet_amount = required - manager_amount;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        manager_amount, // some in manager
        wallet_amount, // rest in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, wallet_amount, manager_amount, 0, true);

    // Treasury exactly matches what's needed
    let user_amount = required / 2;
    let treasury_needed = required - user_amount;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_amount, // some in wallet
        treasury_needed, // exact treasury reserves needed
    );
    assert_deep_plan_eq(plan, user_amount, 0, treasury_needed, true);
}

#[test]
fun one_token_boundaries() {
    // Tests with just one token difference
    let required = DEEP_MEDIUM;

    // Manager has one token less than required
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required - 1, // one token less in manager
        0, // nothing in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);

    // One token in wallet completes the requirement
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        required - 1, // one token less in manager
        1, // one token in wallet
        0, // no treasury reserves
    );
    assert_deep_plan_eq(plan, 1, required - 1, 0, true);

    // One token short with treasury
    let user_amount = required / 2;
    let treasury_needed = required - user_amount;
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_amount, // some in wallet
        treasury_needed - 1, // one token short in treasury
    );
    assert_deep_plan_eq(plan, 0, 0, 0, false);

    // One extra token in treasury
    let plan = get_deep_plan(
        false, // not whitelisted
        required, // deep required
        0, // nothing in manager
        user_amount, // some in wallet
        treasury_needed + 1, // one token extra in treasury
    );
    assert_deep_plan_eq(plan, user_amount, 0, treasury_needed, true);
}
