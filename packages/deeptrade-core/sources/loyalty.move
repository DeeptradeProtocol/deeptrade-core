/// Loyalty Program Module
///
/// This module implements a loyalty reward system that provides protocol fee discounts to users
/// based on their assigned loyalty levels. The system is designed to provide benefits to active traders.
///
/// User loyalty levels are fully determined by the protocol governance (admin).
/// For detailed information about the loyalty program, see the docs/loyalty.md documentation.
module deeptrade_core::loyalty;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::multisig_config::MultisigConfig;
use sui::event;
use sui::table::{Self, Table};

// === Errors ===
const ELoyaltyLevelNotFound: u64 = 1;
const ELoyaltyLevelAlreadyExists: u64 = 2;
const ELoyaltyLevelHasUsers: u64 = 3;
const EUserAlreadyHasLoyaltyLevel: u64 = 4;
const EUserHasNoLoyaltyLevel: u64 = 5;
const EInvalidFeeDiscountRate: u64 = 6;
const ESenderIsNotLoyaltyAdmin: u64 = 7;

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

/// A capability to grant and revoke user loyalty levels without protocol admin participation.
/// This avoids the need for multisig approval, allowing for frequent user level updates.
public struct LoyaltyAdminCap has key {
    id: UID,
    owner: address,
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

public struct LoyaltyAdminCapOwnerUpdated has copy, drop {
    loyalty_admin_cap_id: ID,
    old_owner: address,
    new_owner: address,
}

fun init(ctx: &mut TxContext) {
    let loyalty_program = LoyaltyProgram {
        id: object::new(ctx),
        user_levels: table::new(ctx),
        levels: table::new(ctx),
    };
    let admin_cap = LoyaltyAdminCap {
        id: object::new(ctx),
        owner: ctx.sender(),
    };

    transfer::share_object(admin_cap);
    transfer::share_object(loyalty_program);
}

// === Public-Mutative Functions ===
/// Assign a new loyalty admin by updating the owner of the loyalty admin cap.
/// A protocol admin operation.
public fun update_loyalty_admin_cap_owner(
    loyalty_admin_cap: &mut LoyaltyAdminCap,
    multisig_config: &MultisigConfig,
    _admin_cap: &AdminCap,
    new_owner: address,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);

    let old_owner = loyalty_admin_cap.owner;
    loyalty_admin_cap.owner = new_owner;

    event::emit(LoyaltyAdminCapOwnerUpdated {
        loyalty_admin_cap_id: loyalty_admin_cap.id.to_inner(),
        old_owner,
        new_owner,
    });
}

/// Grant a user a loyalty level
public fun grant_user_level(
    loyalty_program: &mut LoyaltyProgram,
    admin: &LoyaltyAdminCap,
    user: address,
    level: u8,
    ctx: &mut TxContext,
) {
    validate_loyalty_admin_cap(admin, ctx);

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
    admin: &LoyaltyAdminCap,
    user: address,
    ctx: &mut TxContext,
) {
    validate_loyalty_admin_cap(admin, ctx);

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
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    level: u8,
    fee_discount_rate: u64,
    ctx: &mut TxContext,
) {
    // Validate multisig
    multisig_config.validate_sender_is_admin_multisig(ctx);

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
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    level: u8,
    ctx: &mut TxContext,
) {
    // Validate multisig
    multisig_config.validate_sender_is_admin_multisig(ctx);

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

// === Private Functions ===
/// Validate that the sender is the owner of the loyalty admin cap
fun validate_loyalty_admin_cap(loyalty_admin_cap: &LoyaltyAdminCap, ctx: &TxContext) {
    assert!(loyalty_admin_cap.owner == ctx.sender(), ESenderIsNotLoyaltyAdmin);
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

/// Get the owner of the `LoyaltyAdminCap` for testing purposes.
#[test_only]
public fun owner_for_testing(loyalty_admin_cap: &LoyaltyAdminCap): address {
    loyalty_admin_cap.owner
}
