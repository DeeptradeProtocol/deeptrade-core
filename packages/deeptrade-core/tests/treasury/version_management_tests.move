#[test_only]
module deeptrade_core::version_management_tests;

use deeptrade_core::admin::AdminCap;
use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::helper::current_version;
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use deeptrade_core::treasury::{
    Self,
    Treasury,
    VersionEnabled,
    VersionDisabled,
    unwrap_version_enabled_event,
    unwrap_version_disabled_event,
    EPackageVersionNotEnabled,
    EVersionPermanentlyDisabled,
    EVersionAlreadyEnabled,
    EVersionNotEnabled,
    ECannotDisableNewerVersion
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::event;
use sui::test_scenario::{Self, Scenario};

const NEW_VERSION: u16 = 2;
const FAKE_USER: address = @0xFA; // Add this

#[test]
fun test_enable_new_version_success() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, treasury_id) = setup();

    scenario.next_tx(multisig_address);
    {
        let new_version = NEW_VERSION;
        assert!(!treasury.allowed_versions().contains(&new_version), 1);
        let config = scenario.take_shared<MultisigConfig>();

        treasury::enable_version(
            &mut treasury,
            &config,
            &admin_cap,
            NEW_VERSION,
            scenario.ctx(),
        );

        assert!(treasury.allowed_versions().contains(&new_version), 2);

        // Verify event
        let enabled_events = event::events_by_type<VersionEnabled>();
        assert!(enabled_events.length() == 1, 3);
        let (event_treasury_id, event_version) = unwrap_version_enabled_event(
            &enabled_events[0],
        );
        assert!(event_treasury_id == treasury_id, 4);
        assert!(event_version == NEW_VERSION, 5);
        test_scenario::return_shared(config);
    };

    test_scenario::return_shared(treasury);
    scenario.return_to_sender(admin_cap);

    scenario.end();
}

#[test]
fun test_disable_current_version_success() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, treasury_id) = setup();

    scenario.next_tx(multisig_address);
    {
        let version_to_disable = current_version();
        let config = scenario.take_shared<MultisigConfig>();

        assert!(treasury.allowed_versions().contains(&version_to_disable), 1);
        assert!(!treasury.disabled_versions().contains(&version_to_disable), 2);

        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            version_to_disable,
            scenario.ctx(),
        );

        assert!(!treasury.allowed_versions().contains(&version_to_disable), 3);
        assert!(treasury.disabled_versions().contains(&version_to_disable), 4);

        // Verify event
        let disabled_events = event::events_by_type<VersionDisabled>();
        assert!(disabled_events.length() == 1, 5);
        let (event_treasury_id, event_version) = unwrap_version_disabled_event(
            &disabled_events[0],
        );
        assert!(event_treasury_id == treasury_id, 6);
        assert!(event_version == version_to_disable, 7);
        test_scenario::return_shared(config);
    };

    test_scenario::return_shared(treasury);
    scenario.return_to_sender(admin_cap);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = EPackageVersionNotEnabled)]
fun test_action_fails_on_disabled_version() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, _) = setup();
    let version_to_disable = current_version();

    // Disable the current version
    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            version_to_disable,
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    // Attempt to perform a version-checked action
    scenario.next_tx(multisig_address);
    {
        // let mut treasury = scenario.take_shared<Treasury>();
        let deep_coin = sui::coin::mint_for_testing<token::deep::DEEP>(1, scenario.ctx());

        // This should fail because the version is disabled
        treasury::deposit_into_reserves(&mut treasury, deep_coin);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = EVersionPermanentlyDisabled)]
fun test_reenable_disabled_version_fails() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, _) = setup();
    let version_to_disable = current_version();

    // Disable the current version
    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            version_to_disable,
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    // Attempt to re-enable the disabled version
    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // This should fail
        treasury::enable_version(
            &mut treasury,
            &config,
            &admin_cap,
            version_to_disable,
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);

    scenario.end();
}

#[test]
#[expected_failure(abort_code = EVersionAlreadyEnabled)]
fun test_enable_version_fails_already_enabled() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, _) = setup();

    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // Attempt to enable the current version, which is already enabled by default
        treasury::enable_version(
            &mut treasury,
            &config,
            &admin_cap,
            current_version(),
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = EVersionNotEnabled)]
fun test_disable_version_fails_not_enabled() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, _) = setup();

    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // Disable the current version
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            current_version(),
            scenario.ctx(),
        );

        // Disable the version that is not enabled (we already disabled the current version)
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            current_version(),
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ECannotDisableNewerVersion)]
fun test_disable_version_fails_newer_version() {
    let (mut scenario, multisig_address, admin_cap, mut treasury, _) = setup();

    scenario.next_tx(multisig_address);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // Attempt to disable a future version
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            current_version() + 1,
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun test_version_management_fails_not_multisig() {
    let (mut scenario, _, admin_cap, mut treasury, _) = setup();

    // Switch to a non-multisig user
    scenario.next_tx(FAKE_USER);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // Attempt to enable a version from an unauthorized address
        treasury::enable_version(
            &mut treasury,
            &config,
            &admin_cap,
            NEW_VERSION,
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ESenderIsNotValidMultisig)]
fun test_version_management_fails_not_multisig_disable() {
    let (mut scenario, _, admin_cap, mut treasury, _) = setup();

    // Switch to a non-multisig user
    scenario.next_tx(FAKE_USER);
    {
        let config = scenario.take_shared<MultisigConfig>();
        // Attempt to enable a version from an unauthorized address
        treasury::disable_version(
            &mut treasury,
            &config,
            &admin_cap,
            current_version(),
            scenario.ctx(),
        );
        test_scenario::return_shared(config);
    };

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(treasury);
    scenario.end();
}

// === Helper Functions ===

#[test_only]
fun setup(): (Scenario, address, AdminCap, Treasury, ID) {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);
    treasury::init_for_testing(scenario.ctx());

    // Initialise treasury
    scenario.next_tx(multisig_address);
    scenario.next_tx(multisig_address);
    let admin_cap = scenario.take_from_sender<AdminCap>();
    let treasury = scenario.take_shared<Treasury>();
    let treasury_id = object::id(&treasury);

    (scenario, multisig_address, admin_cap, treasury, treasury_id)
}
