module deeptrade_core::ticket;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::multisig_config::MultisigConfig;
use sui::clock::Clock;
use sui::event;

// === Errors ===
const ETicketOwnerMismatch: u64 = 1;
const ETicketTypeMismatch: u64 = 2;
const ETicketExpired: u64 = 3;
const ETicketNotReady: u64 = 4;
const ETicketNotExpired: u64 = 5;

// === Constants ===
const MILLISECONDS_PER_DAY: u64 = 86_400_000;
const TICKET_DELAY_DURATION: u64 = MILLISECONDS_PER_DAY * 2; // 2 days
const TICKET_ACTIVE_DURATION: u64 = MILLISECONDS_PER_DAY * 3; // 3 days

/// Ticket types
const WITHDRAW_DEEP_RESERVES: u8 = 0;
const WITHDRAW_PROTOCOL_FEE: u8 = 1;
const WITHDRAW_COVERAGE_FEE: u8 = 2;
const UPDATE_POOL_CREATION_PROTOCOL_FEE: u8 = 3;
const UPDATE_DEFAULT_FEES: u8 = 4;
const UPDATE_POOL_SPECIFIC_FEES: u8 = 5;

// === Structs ===
/// Admin ticket for timelock mechanism
public struct AdminTicket has key {
    id: UID,
    owner: address,
    created_at: u64,
    ticket_type: u8,
}

// === Events ===
/// Event emitted when an admin ticket is created
public struct TicketCreated has copy, drop {
    ticket_id: ID,
    ticket_type: u8,
}

/// Event emitted when a ticket is destroyed (consumed or expired)
public struct TicketDestroyed has copy, drop {
    ticket_id: ID,
    ticket_type: u8,
    // Whether the ticket was expired (true) or consumed (false)
    is_expired: bool,
}

// === Public Functions ===
/// Create an admin ticket for timelock mechanism with multi-signature verification
/// Verifies sender matches the admin multi-sig address, then creates a ticket for future execution
///
/// Parameters:
/// - multisig_config: Protocol's admin multisig config
/// - _admin: Admin capability
/// - ticket_type: Type of operation this ticket authorizes
/// - clock: Clock for timestamp recording
/// - ctx: Mutable transaction context for ticket creation and sender verification
///
/// Returns:
/// - AdminTicket: The created ticket bound to the sender address
///
/// Aborts:
/// - With ESenderIsNotValidMultisig if the transaction sender is not the protocol's admin multisig
public fun create_ticket(
    multisig_config: &MultisigConfig,
    _admin: &AdminCap,
    ticket_type: u8,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    multisig_config.validate_sender_is_admin_multisig(ctx);

    let created_at = clock.timestamp_ms();

    let ticket = AdminTicket {
        id: object::new(ctx),
        owner: ctx.sender(),
        created_at,
        ticket_type,
    };

    event::emit(TicketCreated {
        ticket_id: ticket.id.to_inner(),
        ticket_type,
    });

    transfer::share_object(ticket)
}

/// Cleans up an expired admin ticket
/// Any user can call this function to remove an expired ticket from the system
public fun cleanup_expired_ticket(ticket: AdminTicket, clock: &Clock) {
    assert!(is_ticket_expired(&ticket, clock), ETicketNotExpired);

    destroy_ticket(ticket, clock);
}

// === Public-View Functions ===
/// Check if ticket is ready for execution (past delay period)
public fun is_ticket_ready(ticket: &AdminTicket, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    current_time >= ticket.created_at + TICKET_DELAY_DURATION
}

/// Check if ticket is expired (past active period)
public fun is_ticket_expired(ticket: &AdminTicket, clock: &Clock): bool {
    let current_time = clock.timestamp_ms();
    current_time >= ticket.created_at + TICKET_DELAY_DURATION + TICKET_ACTIVE_DURATION
}

public fun ticket_delay_duration(): u64 { TICKET_DELAY_DURATION }

public fun ticket_active_duration(): u64 { TICKET_ACTIVE_DURATION }

public fun withdraw_deep_reserves_ticket_type(): u8 { WITHDRAW_DEEP_RESERVES }

public fun withdraw_protocol_fee_ticket_type(): u8 { WITHDRAW_PROTOCOL_FEE }

public fun withdraw_coverage_fee_ticket_type(): u8 { WITHDRAW_COVERAGE_FEE }

public fun update_pool_creation_protocol_fee_ticket_type(): u8 { UPDATE_POOL_CREATION_PROTOCOL_FEE }

public fun update_default_fees_ticket_type(): u8 { UPDATE_DEFAULT_FEES }

public fun update_pool_specific_fees_ticket_type(): u8 { UPDATE_POOL_SPECIFIC_FEES }

// === Package Functions ===
/// Consumes the ticket, should be called after validation.
public(package) fun destroy_ticket(ticket: AdminTicket, clock: &Clock) {
    let is_expired = is_ticket_expired(&ticket, clock);

    let AdminTicket { id, ticket_type, .. } = ticket;

    event::emit(TicketDestroyed {
        ticket_id: id.to_inner(),
        ticket_type,
        is_expired,
    });

    id.delete();
}

/// Validate ticket for execution
public(package) fun validate_ticket(
    ticket: &AdminTicket,
    expected_type: u8,
    clock: &Clock,
    ctx: &TxContext,
) {
    // Check ownership
    assert!(ticket.owner == ctx.sender(), ETicketOwnerMismatch);
    // Check type
    assert!(ticket.ticket_type == expected_type, ETicketTypeMismatch);
    // Check if expired
    assert!(!is_ticket_expired(ticket, clock), ETicketExpired);
    // Check if ready
    assert!(is_ticket_ready(ticket, clock), ETicketNotReady);
}

// === Test Functions ===
#[test_only]
public fun owner(ticket: &AdminTicket): address { ticket.owner }

#[test_only]
public fun created_at(ticket: &AdminTicket): u64 { ticket.created_at }

#[test_only]
public fun ticket_type(ticket: &AdminTicket): u8 { ticket.ticket_type }

#[test_only]
public fun unwrap_ticket_created_event(event: &TicketCreated): (ID, u8) {
    (event.ticket_id, event.ticket_type)
}

#[test_only]
public fun unwrap_ticket_destroyed_event(event: &TicketDestroyed): (ID, u8, bool) {
    (event.ticket_id, event.ticket_type, event.is_expired)
}
