#[test_only]
module deeptrade_core::prepare_order_execution_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{create_acct_and_share_with_funds, USDC};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::{setup_test, setup_pool_with_default_fees, setup_reference_pool};
use deeptrade_core::dt_order::prepare_order_execution;
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::get_sui_per_deep_from_oracle_tests::{
    new_deep_price_object,
    new_sui_price_object
};
use deeptrade_core::helper::hundred_percent;
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use deeptrade_core::treasury::{Self, Treasury};
use pyth::price_info;
use std::unit_test::assert_eq;
use sui::clock;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const USDC_MULTIPLIER: u64 = 1_000_000; // For USDC (6 decimals)
const SUI_MULTIPLIER: u64 = 1_000_000_000; // For SUI (9 decimals)
const DEEP_MULTIPLIER: u64 = 1_000_000; // For DEEP (6 decimals)

#[test]
fun bid_success() {
    // Test-specific constants
    let order_amount = 5_000 * USDC_MULTIPLIER; // 5,000 quote tokens for bid
    let deep_required = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP required
    let balance_manager_quote = 1_000 * USDC_MULTIPLIER; // 1,000 quote tokens in BM
    let balance_manager_deep = 500 * DEEP_MULTIPLIER; // 500 DEEP in BM
    let balance_manager_sui = 100 * SUI_MULTIPLIER; // 100 SUI in BM
    let balance_manager_base = 2_000 * SUI_MULTIPLIER; // 2,000 base tokens (SUI) in BM
    let wallet_quote_amount = 5_000 * USDC_MULTIPLIER; // 5,000 quote tokens in wallet
    let wallet_base_amount = 10_000 * SUI_MULTIPLIER; // 10,000 base tokens in wallet
    let wallet_deep_amount = 200 * DEEP_MULTIPLIER; // 200 DEEP in wallet (not enough)
    let wallet_sui_amount = 200 * SUI_MULTIPLIER; // 200 SUI in wallet

    let mut scenario = begin(OWNER);

    // Step 1: Setup treasury, fee config, and loyalty program
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Add DEEP to treasury reserves
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(10_000 * DEEP_MULTIPLIER, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);

    // Create pool setup balance manager with large amounts for reference pool setup
    let pool_setup_bm_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(), // Large amount for pool setup
        &mut scenario,
    );

    // Create user balance manager with specific amounts for testing
    let user_bm_id = create_acct_and_share_with_funds(
        ALICE,
        0, // Start with 0 funds, we'll add specific amounts later
        &mut scenario,
    );

    // Add specific amounts to user balance manager
    scenario.next_tx(ALICE);
    {
        let mut user_bm = scenario.take_shared_by_id<BalanceManager>(user_bm_id);
        let quote_coin = mint_for_testing<USDC>(balance_manager_quote, scenario.ctx());
        let deep_coin = mint_for_testing<DEEP>(balance_manager_deep, scenario.ctx());
        let sui_coin = mint_for_testing<SUI>(balance_manager_sui, scenario.ctx());
        let base_coin = mint_for_testing<SUI>(balance_manager_base, scenario.ctx());

        user_bm.deposit(quote_coin, scenario.ctx());
        user_bm.deposit(deep_coin, scenario.ctx());
        user_bm.deposit(sui_coin, scenario.ctx());
        user_bm.deposit(base_coin, scenario.ctx());

        return_shared(user_bm);
    };

    // Step 3: Create trading pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        false, // whitelisted_pool = false
        false, // stable_pool = false
        &mut scenario,
    );

    // Step 4: Create reference pool (DEEP/SUI) using pool setup balance manager
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        pool_setup_bm_id, // Use pool setup balance manager
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Step 5: Create price info objects
    let clock = clock::create_for_testing(scenario.ctx());
    let current_time = clock::timestamp_ms(&clock);

    let deep_price = new_deep_price_object(
        &mut scenario,
        300_000_000, // DEEP price magnitude (3 USD per DEEP)
        false, // positive
        1, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        500_000_000, // SUI price magnitude (5 USD per SUI)
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );

    // Step 6: Create wallet coins
    scenario.next_tx(ALICE);
    let mut base_coin = mint_for_testing<SUI>(wallet_base_amount, scenario.ctx());
    let mut quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());
    let mut deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());
    let mut sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 7: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(user_bm_id);

        // Record initial balances
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_bm_deep_balance = balance_manager.balance<DEEP>();
        let initial_bm_sui_balance = balance_manager.balance<SUI>();
        let initial_wallet_quote_balance = quote_coin.value();
        let initial_wallet_base_balance = base_coin.value();
        let initial_wallet_deep_balance = deep_coin.value();
        let initial_treasury_deep_balance = treasury.deep_reserves();

        // Execute prepare_order_execution
        let (trade_proof, discount_rate) = prepare_order_execution(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &mut balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &mut deep_coin,
            &mut sui_coin,
            deep_required,
            order_amount,
            true, // is_bid
            1_000_000 * DEEP_MULTIPLIER, // estimated_deep_required (use large to avoid fail from slippage validation)
            10_000_000, // estimated_deep_required_slippage (1%)
            100_000_000 * SUI_MULTIPLIER, // estimated_sui_fee (use large to avoid fail from slippage validation)
            10_000_000, // estimated_sui_fee_slippage (1%)
            &clock,
            scenario.ctx(),
        );

        // Step 8: Verify results

        // Verify valid trade proof is returned
        balance_manager.validate_proof(&trade_proof);

        // Verify discount rate is reasonable (0-100%)
        assert!(discount_rate <= hundred_percent());

        // Verify side effects: conservation of funds
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        let final_bm_deep_balance = balance_manager.balance<DEEP>();
        let final_bm_sui_balance = balance_manager.balance<SUI>();
        let final_wallet_quote_balance = quote_coin.value();
        let final_wallet_base_balance = base_coin.value();
        let final_wallet_deep_balance = deep_coin.value();
        let final_treasury_deep_balance = treasury.deep_reserves();

        // Conservation of funds: what was withdrawn equals what was deposited
        let quote_deposited = final_bm_quote_balance - initial_bm_quote_balance;
        let quote_withdrawn = initial_wallet_quote_balance - final_wallet_quote_balance;
        assert_eq!(quote_deposited, quote_withdrawn);

        // Verify some funds were actually moved (not a no-op)
        assert!(quote_deposited > 0);

        let deep_deposited = final_bm_deep_balance - initial_bm_deep_balance;
        let deep_from_treasury = initial_treasury_deep_balance - final_treasury_deep_balance;

        // DEEP coins are consumed and we can track wallet changes
        // We can verify that DEEP was deposited to balance manager from treasury + wallet
        // Total DEEP deposited should be at least the amount taken from treasury
        let deep_consumed = initial_wallet_deep_balance - final_wallet_deep_balance;
        assert_eq!(deep_deposited, deep_from_treasury + deep_consumed);
        assert!(deep_from_treasury > 0);
        assert!(deep_consumed > 0);

        // Verify base tokens remain unchanged (not used for bid)
        // Note: Base tokens (SUI) might be used for coverage fees since SUI is both base and coverage fee token
        // So we only verify that wallet base tokens remain unchanged
        assert_eq!(final_wallet_base_balance, initial_wallet_base_balance);

        // We can verify that SUI was taken from balance manager for coverage fees
        let sui_taken_from_bm = initial_bm_sui_balance - final_bm_sui_balance;
        let treasury_coverage_fee_balance = treasury.get_deep_reserves_coverage_fee_balance<SUI>();
        // Coverage fees go directly to treasury, not to balance manager
        // Treasury coverage fee balance equals SUI taken from balance manager
        // (SUI is base token, not input token, so only used for coverage fees)
        assert_eq!(treasury_coverage_fee_balance, sui_taken_from_bm);
        // Balance manager SUI decreases by amount taken for coverage fees
        assert!(sui_taken_from_bm > 0);

        // Cleanup
        destroy(base_coin);
        destroy(quote_coin);
        destroy(deep_coin);
        destroy(sui_coin);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(reference_pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
        return_shared(treasury);
        clock::destroy_for_testing(clock);
        price_info::destroy(deep_price);
        price_info::destroy(sui_price);
    };

    scenario.end();
}

#[test]
fun ask_success() {
    // Test-specific constants
    let order_amount = 8_000 * SUI_MULTIPLIER; // 8,000 base tokens for ask
    let deep_required = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP required
    let balance_manager_base = 2_000 * SUI_MULTIPLIER; // 2,000 base tokens in BM
    let balance_manager_deep = 500 * DEEP_MULTIPLIER; // 500 DEEP in BM
    let balance_manager_sui = 100 * SUI_MULTIPLIER; // 100 SUI in BM
    let balance_manager_quote = 1_000 * USDC_MULTIPLIER; // 1,000 quote tokens in BM
    let wallet_base_amount = 10_000 * SUI_MULTIPLIER; // 10,000 base tokens in wallet
    let wallet_quote_amount = 5_000 * USDC_MULTIPLIER; // 5,000 quote tokens in wallet (unused for ask)
    let wallet_deep_amount = 200 * DEEP_MULTIPLIER; // 200 DEEP in wallet (not enough)
    let wallet_sui_amount = 200 * SUI_MULTIPLIER; // 200 SUI in wallet

    let mut scenario = begin(OWNER);

    // Step 1: Setup treasury, fee config, and loyalty program
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Add DEEP to treasury reserves
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(10_000 * DEEP_MULTIPLIER, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);

    // Create pool setup balance manager with large amounts for reference pool setup
    let pool_setup_bm_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(), // Large amount for pool setup
        &mut scenario,
    );

    // Create user balance manager with specific amounts for testing
    let user_bm_id = create_acct_and_share_with_funds(
        ALICE,
        0, // Start with 0 funds, we'll add specific amounts later
        &mut scenario,
    );

    // Add specific amounts to user balance manager
    scenario.next_tx(ALICE);
    {
        let mut user_bm = scenario.take_shared_by_id<BalanceManager>(user_bm_id);
        let base_coin = mint_for_testing<SUI>(balance_manager_base, scenario.ctx());
        let deep_coin = mint_for_testing<DEEP>(balance_manager_deep, scenario.ctx());
        let sui_coin = mint_for_testing<SUI>(balance_manager_sui, scenario.ctx());
        let quote_coin = mint_for_testing<USDC>(balance_manager_quote, scenario.ctx());

        user_bm.deposit(base_coin, scenario.ctx());
        user_bm.deposit(deep_coin, scenario.ctx());
        user_bm.deposit(sui_coin, scenario.ctx());
        user_bm.deposit(quote_coin, scenario.ctx());

        return_shared(user_bm);
    };

    // Step 3: Create trading pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        false, // whitelisted_pool = false
        false, // stable_pool = false
        &mut scenario,
    );

    // Step 4: Create reference pool (DEEP/SUI) using pool setup balance manager
    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        pool_setup_bm_id, // Use pool setup balance manager
        100 * constants::float_scaling(), // deep_multiplier = 100
        &mut scenario,
    );

    // Step 5: Create price info objects
    let clock = clock::create_for_testing(scenario.ctx());
    let current_time = clock::timestamp_ms(&clock);

    let deep_price = new_deep_price_object(
        &mut scenario,
        300_000_000, // DEEP price magnitude (3 USD per DEEP)
        false, // positive
        1, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        500_000_000, // SUI price magnitude (5 USD per SUI)
        false, // positive
        0, // confidence
        8, // exponent
        true, // negative exponent
        current_time,
    );

    // Step 6: Create wallet coins
    scenario.next_tx(ALICE);
    let mut base_coin = mint_for_testing<SUI>(wallet_base_amount, scenario.ctx());
    let mut quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());
    let mut deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());
    let mut sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 7: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(user_bm_id);

        // Record initial balances
        let initial_bm_base_balance = balance_manager.balance<SUI>();
        let initial_bm_deep_balance = balance_manager.balance<DEEP>();
        let initial_wallet_base_balance = base_coin.value();
        let initial_wallet_deep_balance = deep_coin.value();
        let initial_treasury_deep_balance = treasury.deep_reserves();

        // Execute prepare_order_execution
        let (trade_proof, discount_rate) = prepare_order_execution(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &mut balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &mut deep_coin,
            &mut sui_coin,
            deep_required,
            order_amount,
            false, // is_ask
            1_000_000 * DEEP_MULTIPLIER, // estimated_deep_required (use large to avoid fail from slippage validation)
            10_000_000, // estimated_deep_required_slippage (1%)
            100_000_000 * SUI_MULTIPLIER, // estimated_sui_fee (use large to avoid fail from slippage validation)
            10_000_000, // estimated_sui_fee_slippage (1%)
            &clock,
            scenario.ctx(),
        );

        // Step 8: Verify results

        // Verify valid trade proof is returned
        balance_manager.validate_proof(&trade_proof);

        // Verify discount rate is reasonable (0-100%)
        assert!(discount_rate <= hundred_percent());

        // Verify side effects: conservation of funds
        let final_bm_base_balance = balance_manager.balance<SUI>();
        let final_bm_deep_balance = balance_manager.balance<DEEP>();
        let final_wallet_base_balance = base_coin.value();
        let final_wallet_deep_balance = deep_coin.value();
        let final_treasury_deep_balance = treasury.deep_reserves();

        // For ask orders, SUI is both input coin and coverage fee token
        // So we can't do simple conservation check like with bid orders
        let base_deposited = final_bm_base_balance - initial_bm_base_balance;
        let base_withdrawn = initial_wallet_base_balance - final_wallet_base_balance;

        // Verify some funds were actually moved (not a no-op)
        // For ask orders: base_withdrawn > base_deposited because some SUI is used for coverage fees
        assert!(base_withdrawn > 0);
        assert!(base_withdrawn > base_deposited);

        let deep_deposited = final_bm_deep_balance - initial_bm_deep_balance;
        let deep_from_treasury = initial_treasury_deep_balance - final_treasury_deep_balance;

        // DEEP coins are consumed and we can track wallet changes
        // We can verify that DEEP was deposited to balance manager from treasury + wallet
        // Total DEEP deposited should be at least the amount taken from treasury
        let deep_consumed = initial_wallet_deep_balance - final_wallet_deep_balance;
        assert_eq!(deep_deposited, deep_from_treasury + deep_consumed);
        assert!(deep_from_treasury > 0);
        assert!(deep_consumed > 0);

        // Verify quote tokens remain unchanged (not used for ask)
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        let final_wallet_quote_balance = quote_coin.value();
        assert_eq!(final_bm_quote_balance, balance_manager_quote);
        assert_eq!(final_wallet_quote_balance, wallet_quote_amount);

        // Verify SUI balance changes (coverage fees)
        // For ask orders, SUI is both input coin and coverage fee token
        // So we can't track coverage fees separately since SUI gets deposited as input coin
        let treasury_coverage_fee_balance = treasury.get_deep_reserves_coverage_fee_balance<SUI>();
        // Coverage fees should be collected in treasury
        assert!(treasury_coverage_fee_balance > 0);

        // Cleanup
        destroy(base_coin);
        destroy(quote_coin);
        destroy(deep_coin);
        destroy(sui_coin);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(reference_pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
        return_shared(treasury);
        clock::destroy_for_testing(clock);
        price_info::destroy(deep_price);
        price_info::destroy(sui_price);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInvalidOwner)]
fun invalid_owner_aborts() {
    // This test verifies that prepare_order_execution aborts when called by someone
    // who is not the owner of the balance manager

    let mut scenario = begin(OWNER);

    // Setup basic infrastructure
    scenario.next_tx(OWNER);
    {
        treasury::init_for_testing(scenario.ctx());
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Add DEEP to treasury reserves
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(10_000 * DEEP_MULTIPLIER, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);

    // Create pool setup balance manager
    let pool_setup_bm_id = create_acct_and_share_with_funds(
        ALICE,
        1000000 * constants::float_scaling(),
        &mut scenario,
    );

    // Create user balance manager owned by ALICE
    let user_bm_id = create_acct_and_share_with_funds(
        ALICE,
        0,
        &mut scenario,
    );

    // Create trading pool and reference pool
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        false,
        false,
        &mut scenario,
    );

    let reference_pool_id = setup_reference_pool<DEEP, SUI>(
        ALICE,
        registry_id,
        pool_setup_bm_id,
        100 * constants::float_scaling(),
        &mut scenario,
    );

    // Create price info objects
    let clock = clock::create_for_testing(scenario.ctx());
    let current_time = clock::timestamp_ms(&clock);

    let deep_price = new_deep_price_object(
        &mut scenario,
        300_000_000,
        false,
        1,
        8,
        true,
        current_time,
    );
    let sui_price = new_sui_price_object(
        &mut scenario,
        500_000_000,
        false,
        0,
        8,
        true,
        current_time,
    );

    // Create wallet coins
    scenario.next_tx(ALICE);
    let mut base_coin = mint_for_testing<SUI>(10_000 * SUI_MULTIPLIER, scenario.ctx());
    let mut quote_coin = mint_for_testing<USDC>(5_000 * USDC_MULTIPLIER, scenario.ctx());
    let mut deep_coin = mint_for_testing<DEEP>(200 * DEEP_MULTIPLIER, scenario.ctx());
    let mut sui_coin = mint_for_testing<SUI>(200 * SUI_MULTIPLIER, scenario.ctx());

    // Execute the test with BOB (not the owner)
    scenario.next_tx(BOB);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let reference_pool = scenario.take_shared_by_id<Pool<DEEP, SUI>>(reference_pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(user_bm_id);

        // This should abort because BOB is not the owner of the balance manager
        prepare_order_execution(
            &mut treasury,
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &reference_pool,
            &deep_price,
            &sui_price,
            &mut balance_manager,
            &mut base_coin,
            &mut quote_coin,
            &mut deep_coin,
            &mut sui_coin,
            1_000 * DEEP_MULTIPLIER, // deep_required
            5_000 * USDC_MULTIPLIER, // order_amount
            true, // is_bid
            1_000_000 * DEEP_MULTIPLIER, // estimated_deep_required
            10_000_000, // estimated_deep_required_slippage
            100_000_000 * SUI_MULTIPLIER, // estimated_sui_fee
            10_000_000, // estimated_sui_fee_slippage
            &clock,
            scenario.ctx(),
        );

        // This line should never be reached
        destroy(base_coin);
        destroy(quote_coin);
        destroy(deep_coin);
        destroy(sui_coin);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(reference_pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
        return_shared(treasury);
        clock::destroy_for_testing(clock);
        price_info::destroy(deep_price);
        price_info::destroy(sui_price);
    };

    scenario.end();
}
