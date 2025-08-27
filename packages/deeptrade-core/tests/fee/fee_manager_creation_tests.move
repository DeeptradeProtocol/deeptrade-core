#[test_only]
module deeptrade_core::fee_manager_creation_tests;

use deeptrade_core::fee_manager::{new, share_fee_manager, EInvalidFeeManagerShareTicket};
use sui::test_scenario::{begin, next_tx, end, ctx};

// === Constants ===
const ALICE: address = @0xAAAA;

#[test]
/// Test successful creation and sharing of a fee manager
fun successful_fee_manager_creation_and_sharing() {
    let mut scenario = begin(ALICE);

    // Step 1: Alice creates a new fee manager
    next_tx(&mut scenario, ALICE);
    {
        let (fee_manager, owner_cap, ticket) = new(ctx(&mut scenario));

        // Step 2: Share the fee manager (this should succeed)
        share_fee_manager(fee_manager, ticket);

        // The owner cap should still exist and be transferable
        transfer::public_transfer(owner_cap, ALICE);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EInvalidFeeManagerShareTicket)]
/// Test that sharing fails when ticket has wrong fee manager ID
fun share_fails_with_invalid_ticket() {
    let mut scenario = begin(ALICE);

    // Step 1: Alice creates a new fee manager
    next_tx(&mut scenario, ALICE);
    {
        let (fee_manager, owner_cap, ticket) = new(ctx(&mut scenario));

        // Step 2: Create a different fee manager to get a different ID
        let (fee_manager2, owner_cap2, ticket2) = new(ctx(&mut scenario));

        // Step 3: Try to share fee_manager with ticket2 (wrong ID)
        // This should fail with EInvalidOwner
        share_fee_manager(fee_manager, ticket2);

        // Clean up
        transfer::public_transfer(owner_cap, ALICE);
        transfer::public_transfer(owner_cap2, ALICE);
        share_fee_manager(fee_manager2, ticket);
    };

    end(scenario);
}
