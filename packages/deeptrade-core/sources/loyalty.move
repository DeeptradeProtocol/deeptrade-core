/// Loyalty Program Module
///
/// This module implements a loyalty reward system that provides protocol fee discounts to users
/// based on their assigned loyalty levels. The system is designed to provide benefits to active traders.
///
/// User loyalty levels are fully determined by the protocol governance (admin).
/// For detailed information about the loyalty program, see the docs/loyalty.md documentation.
module deeptrade_core::loyalty;

use deeptrade_core::admin::AdminCap;
use multisig::multisig;
use sui::event;
use sui::table::{Self, Table};

// === Errors ===
const ELoyaltyLevelNotFound: u64 = 1;
const ELoyaltyLevelAlreadyExists: u64 = 2;
const ELoyaltyLevelHasUsers: u64 = 3;
const EUserAlreadyHasLoyaltyLevel: u64 = 4;
const EUserHasNoLoyaltyLevel: u64 = 5;
const EInvalidFeeDiscountRate: u64 = 6;
const ESenderIsNotMultisig: u64 = 7;

// === Constants ===
const MAX_FEE_DISCOUNT_RATE: u64 = 1_000_000_000; // 100% in billionths

// === Structs ===
/// A loyalty program to reward engaged users with benefits.
public struct LoyaltyProgram has key {
    id: UID,
    /// Maps a user's address to their loyalty level ID.
    user_levels: Table<address, u8>,
    /// Maps a loyalty level ID to its level information.
    levels: Table<u8, LoyaltyLevel>,
}

/// Defines the information for a single loyalty level.
public struct LoyaltyLevel has copy, drop, store {
    /// The discount rate on protocol fees for this level.
    fee_discount_rate: u64,
    /// The total number of members currently at this level.
    member_count: u64,
}

// === Events ===
public struct UserLevelGranted has copy, drop {
    loyalty_program_id: ID,
    user: address,
    level: u8,
}

public struct UserLevelRevoked has copy, drop {
    loyalty_program_id: ID,
    user: address,
    level: u8,
}

public struct LoyaltyLevelAdded has copy, drop {
    loyalty_program_id: ID,
    level: u8,
    fee_discount_rate: u64,
}

public struct LoyaltyLevelRemoved has copy, drop {
    loyalty_program_id: ID,
    level: u8,
}

fun init(ctx: &mut TxContext) {
    let loyalty_program = LoyaltyProgram {
        id: object::new(ctx),
        user_levels: table::new(ctx),
        levels: table::new(ctx),
    };
    transfer::share_object(loyalty_program);
}

// === Public-Mutative Functions ===
/// Grant a user a loyalty level
public fun grant_user_level(
    loyalty_program: &mut LoyaltyProgram,
    _admin: &AdminCap,
    user: address,
    level: u8,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    // Validate multisig
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    // Validate level exists
    assert!(loyalty_program.levels.contains(level), ELoyaltyLevelNotFound);

    // Check that user doesn't have any other level granted to prevent multiple levels
    assert!(!loyalty_program.user_levels.contains(user), EUserAlreadyHasLoyaltyLevel);

    // Add user to user_levels table
    loyalty_program.user_levels.add(user, level);

    // Increment level member count
    let level_info = loyalty_program.levels.borrow_mut(level);
    level_info.member_count = level_info.member_count + 1;

    // Emit event
    event::emit(UserLevelGranted {
        loyalty_program_id: loyalty_program.id.to_inner(),
        user,
        level,
    });
}

/// Revoke a user's loyalty level
public fun revoke_user_level(
    loyalty_program: &mut LoyaltyProgram,
    _admin: &AdminCap,
    user: address,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    // Validate multisig
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    // Check user has a level assigned
    assert!(loyalty_program.user_levels.contains(user), EUserHasNoLoyaltyLevel);

    let level = *loyalty_program.user_levels.borrow(user);

    // Sanity check: verify the level exists in levels table
    // This should never fail because:
    // 1. The user can only be granted an existing level
    // 2. A level cannot be removed if it has members
    assert!(loyalty_program.levels.contains(level), ELoyaltyLevelNotFound);

    // Remove from user_levels table
    loyalty_program.user_levels.remove(user);

    // Decrement level member count
    let level_info = loyalty_program.levels.borrow_mut(level);
    level_info.member_count = level_info.member_count - 1;

    // Emit event
    event::emit(UserLevelRevoked {
        loyalty_program_id: loyalty_program.id.to_inner(),
        user,
        level,
    });
}

/// Add a new loyalty level with fee discount rate
public fun add_loyalty_level(
    loyalty_program: &mut LoyaltyProgram,
    _admin: &AdminCap,
    level: u8,
    fee_discount_rate: u64,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    // Validate multisig
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    // Validate fee discount rate
    assert!(
        fee_discount_rate > 0 && fee_discount_rate <= MAX_FEE_DISCOUNT_RATE,
        EInvalidFeeDiscountRate,
    );

    // Check level doesn't already exist
    assert!(!loyalty_program.levels.contains(level), ELoyaltyLevelAlreadyExists);

    // Add level with zero member count
    loyalty_program.levels.add(level, LoyaltyLevel { fee_discount_rate, member_count: 0 });

    // Emit event
    event::emit(LoyaltyLevelAdded {
        loyalty_program_id: loyalty_program.id.to_inner(),
        level,
        fee_discount_rate,
    });
}

/// Remove a loyalty level (only if no users have this level)
public fun remove_loyalty_level(
    loyalty_program: &mut LoyaltyProgram,
    _admin: &AdminCap,
    level: u8,
    pks: vector<vector<u8>>,
    weights: vector<u8>,
    threshold: u16,
    ctx: &mut TxContext,
) {
    // Validate multisig
    assert!(
        multisig::check_if_sender_is_multisig_address(pks, weights, threshold, ctx),
        ESenderIsNotMultisig,
    );

    // Validate level exists
    assert!(loyalty_program.levels.contains(level), ELoyaltyLevelNotFound);

    // Check no users have this level
    let level_info = loyalty_program.levels.borrow(level);
    assert!(level_info.member_count == 0, ELoyaltyLevelHasUsers);

    // Remove level
    loyalty_program.levels.remove(level);

    // Emit event
    event::emit(LoyaltyLevelRemoved {
        loyalty_program_id: loyalty_program.id.to_inner(),
        level,
    });
}

// === Public-View Functions ===
/// Get user's loyalty level, returns None if user has no level
public fun get_user_loyalty_level(loyalty_program: &LoyaltyProgram, user: address): Option<u8> {
    if (loyalty_program.user_levels.contains(user))
        option::some(*loyalty_program.user_levels.borrow(user)) else option::none()
}

/// Get fee discount rate for a level, returns None if level doesn't exist
public fun get_loyalty_level_fee_discount_rate(
    loyalty_program: &LoyaltyProgram,
    level: u8,
): Option<u64> {
    if (loyalty_program.levels.contains(level))
        option::some(loyalty_program.levels.borrow(level).fee_discount_rate) else option::none()
}

/// Get user's loyalty fee discount rate, returns 0 if user has no loyalty level
public fun get_user_discount_rate(loyalty_program: &LoyaltyProgram, user: address): u64 {
    let mut level_opt = loyalty_program.get_user_loyalty_level(user);
    if (level_opt.is_none()) return 0;
    let level = level_opt.extract();

    let mut discount_rate_opt = loyalty_program.get_loyalty_level_fee_discount_rate(level);
    // Sanity check: user's level must always exist
    if (discount_rate_opt.is_none()) return 0;
    discount_rate_opt.extract()
}

/// Get number of members in a specific level
public fun get_level_member_count(loyalty_program: &LoyaltyProgram, level: u8): u64 {
    if (loyalty_program.levels.contains(level)) loyalty_program.levels.borrow(level).member_count
    else 0
}

/// Get total number of loyalty program members
public fun total_loyalty_program_members(loyalty_program: &LoyaltyProgram): u64 {
    loyalty_program.user_levels.length()
}

// === Test Functions ===
/// Initialize the loyalty program for testing
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx); }

/// Get a reference to the `levels` table for testing purposes.
#[test_only]
public fun levels(loyalty_program: &LoyaltyProgram): &Table<u8, LoyaltyLevel> {
    &loyalty_program.levels
}

/// Get a reference to the `user_levels` table for testing purposes.
#[test_only]
public fun user_levels(loyalty_program: &LoyaltyProgram): &Table<address, u8> {
    &loyalty_program.user_levels
}
