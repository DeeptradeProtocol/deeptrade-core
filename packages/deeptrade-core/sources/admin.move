/// Module that manages administrative capabilities for the Deeptrade Core package.
/// The AdminCap is created once during module initialization and is given to the
/// package publisher. It can be transferred between addresses and is used to
/// authorize privileged operations in the Deeptrade Core package.
/// For a detailed explanation of administrative roles and procedures, see the docs/admin.md documentation.
module deeptrade_core::admin;

public struct AdminCap has key, store {
    id: UID,
}

/// Create and transfer AdminCap to the publisher during module initialization
fun init(ctx: &mut TxContext) {
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        ctx.sender(),
    )
}

// === Test Functions ===
/// Get an AdminCap for testing purposes
#[test_only]
public fun get_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

// Init AdminCap for testing
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx)
}
