#[test_only]
module deeptrade_core::update_default_fees_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::get_ticket_ready_for_consumption;
use deeptrade_core::fee::{
    Self,
    TradingFeeConfig,
    DefaultFeesUpdated,
    new_pool_fee_config,
    unwrap_default_fees_updated_event,
    default_fees
};
use deeptrade_core::ticket::{
    ETicketTypeMismatch,
    TicketDestroyed,
    unwrap_ticket_destroyed_event,
    update_default_fees_ticket_type,
    update_pool_specific_fees_ticket_type
};
use deeptrade_core::trading_fee_config_init_tests::setup_with_trading_fee_config;
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::event;
use sui::test_scenario;

const NEW_TAKER_FEE: u64 = 1_000_000; // 10 bps
const NEW_MAKER_FEE: u64 = 500_000; // 5 bps

/// Test successful update of the default fees
#[test]
fun test_update_default_fees_success() {
    let multisig_address = get_test_multisig_address();
    let mut scenario = setup_with_admin_cap(multisig_address);
    setup_with_trading_fee_config(&mut scenario, multisig_address);

    let ticket_type = update_default_fees_ticket_type();
    let (ticket, ticket_id, clock) = get_ticket_ready_for_consumption(&mut scenario, ticket_type);

    let new_fees = new_pool_fee_config(
        NEW_TAKER_FEE,
        NEW_MAKER_FEE,
        NEW_TAKER_FEE,
        NEW_MAKER_FEE,
        0,
    );

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    let config_id = object::id(&config);
    let old_fees = default_fees(&config);

    fee::update_default_fees(
        &mut config,
        ticket,
        new_fees,
        &clock,
        scenario.ctx(),
    );

    // Verify events
    let consumed_ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(consumed_ticket_events.length() == 1, 1);
    let (event_ticket_id, _, _) = unwrap_ticket_destroyed_event(&consumed_ticket_events[0]);
    assert!(event_ticket_id == ticket_id, 2);

    let updated_fee_events = event::events_by_type<DefaultFeesUpdated>();
    assert!(updated_fee_events.length() == 1, 3);
    let (event_config_id, event_old_fees, event_new_fees) = unwrap_default_fees_updated_event(
        &updated_fee_events[0],
    );
    assert!(event_config_id == config_id, 4);
    assert!(event_old_fees == old_fees, 5);
    assert!(event_new_fees == new_fees, 6);

    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}

/// Test failure when updating default fees with an incorrect ticket type
#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
fun test_update_default_fees_fails_wrong_type() {
    let multisig_address = get_test_multisig_address();
    let mut scenario = setup_with_admin_cap(multisig_address);
    setup_with_trading_fee_config(&mut scenario, multisig_address);

    let wrong_ticket_type = update_pool_specific_fees_ticket_type();
    let (ticket, _, clock) = get_ticket_ready_for_consumption(
        &mut scenario,
        wrong_ticket_type,
    );

    let new_fees = new_pool_fee_config(0, 0, 0, 0, 0);

    scenario.next_tx(multisig_address);
    let mut config: TradingFeeConfig = scenario.take_shared<TradingFeeConfig>();
    fee::update_default_fees(
        &mut config,
        ticket,
        new_fees,
        &clock,
        scenario.ctx(),
    );

    // Cleanup should not be reached
    test_scenario::return_shared(config);
    clock::destroy_for_testing(clock);
    scenario.end();
}
