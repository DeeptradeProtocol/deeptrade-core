#[test_only]
module deeptrade_core::prepare_whitelisted_order_execution_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{create_acct_and_share_with_funds, USDC};
use deepbook::pool::Pool;
use deepbook::pool_tests::{setup_test, setup_pool_with_default_fees};
use deeptrade_core::dt_order::prepare_whitelisted_order_execution;
use deeptrade_core::fee::{Self, TradingFeeConfig};
use deeptrade_core::helper::hundred_percent;
use deeptrade_core::loyalty::{Self, LoyaltyProgram};
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const TOKEN_MULTIPLIER: u64 = 1_000_000;

#[test]
fun bid_success() {
    // Test-specific constants
    let order_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 quote tokens for bid
    let balance_manager_quote = 1_000 * TOKEN_MULTIPLIER; // 1,000 quote tokens in BM
    let wallet_quote_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 quote tokens in wallet
    let wallet_base_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 base tokens in wallet (unused for bid)

    let mut scenario = begin(OWNER);

    // Step 1: Setup fee config and loyalty program
    scenario.next_tx(OWNER);
    {
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_quote,
        &mut scenario,
    );

    // Step 3: Create whitelisted pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        true, // whitelisted_pool = true
        false, // stable_pool = false
        &mut scenario,
    );

    // Step 4: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // Record initial balances
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_bm_base_balance = balance_manager.balance<SUI>();
        let initial_wallet_quote_balance = quote_coin_mut.value();
        let initial_wallet_base_balance = base_coin_mut.value();

        // Execute prepare_whitelisted_order_execution
        let (trade_proof, discount_rate) = prepare_whitelisted_order_execution(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            order_amount,
            true, // is_bid
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify valid trade proof is returned
        balance_manager.validate_proof(&trade_proof);

        // Verify discount rate is reasonable (0-100%)
        assert!(discount_rate <= hundred_percent()); // 100% in billionths

        // Verify side effects: conservation of funds
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        let final_wallet_quote_balance = quote_coin_mut.value();

        let total_deposited = final_bm_quote_balance - initial_bm_quote_balance;
        let total_withdrawn = initial_wallet_quote_balance - final_wallet_quote_balance;

        // Conservation of funds: what was withdrawn from wallet equals what was deposited to BM
        assert_eq!(total_deposited, total_withdrawn);

        // Verify some funds were actually moved (not a no-op)
        assert!(total_deposited > 0);

        // Verify base tokens remain unchanged (not used for bid)
        let final_bm_base_balance = balance_manager.balance<SUI>();
        let final_wallet_base_balance = base_coin_mut.value();
        assert_eq!(final_bm_base_balance, initial_bm_base_balance);
        assert_eq!(final_wallet_base_balance, initial_wallet_base_balance);

        // Cleanup
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
    };

    scenario.end();
}

#[test]
fun ask_success() {
    // Test-specific constants
    let order_amount = 8_000 * TOKEN_MULTIPLIER; // 8,000 base tokens for ask
    let balance_manager_base = 2_000 * TOKEN_MULTIPLIER; // 2,000 base tokens in BM
    let wallet_base_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 base tokens in wallet
    let wallet_quote_amount = 0; // 0 quote tokens in wallet (unused for ask)

    let mut scenario = begin(OWNER);

    // Step 1: Setup fee config and loyalty program
    scenario.next_tx(OWNER);
    {
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_base,
        &mut scenario,
    );

    // Step 3: Create whitelisted pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        true, // whitelisted_pool = true
        false, // stable_pool = false
        &mut scenario,
    );

    // Step 4: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // Record initial balances
        let initial_bm_base_balance = balance_manager.balance<SUI>();
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_wallet_base_balance = base_coin_mut.value();
        let initial_wallet_quote_balance = quote_coin_mut.value();

        // Execute prepare_whitelisted_order_execution
        let (trade_proof, discount_rate) = prepare_whitelisted_order_execution(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            order_amount,
            false, // is_ask
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify valid trade proof is returned
        balance_manager.validate_proof(&trade_proof);

        // Verify discount rate is reasonable (0-100%)
        assert!(discount_rate <= hundred_percent()); // 100% in billionths

        // Verify side effects: conservation of funds
        let final_bm_base_balance = balance_manager.balance<SUI>();
        let final_wallet_base_balance = base_coin_mut.value();

        let total_deposited = final_bm_base_balance - initial_bm_base_balance;
        let total_withdrawn = initial_wallet_base_balance - final_wallet_base_balance;

        // Conservation of funds: what was withdrawn from wallet equals what was deposited to BM
        assert_eq!(total_deposited, total_withdrawn);

        // Verify some funds were actually moved (not a no-op)
        assert!(total_deposited > 0);

        // Verify quote tokens remain unchanged (not used for ask)
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        let final_wallet_quote_balance = quote_coin_mut.value();
        assert_eq!(final_bm_quote_balance, initial_bm_quote_balance);
        assert_eq!(final_wallet_quote_balance, initial_wallet_quote_balance);

        // Cleanup
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInvalidOwner)]
fun invalid_owner_aborts() {
    // Test-specific constants
    let order_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 quote tokens for bid
    let balance_manager_quote = 1_000 * TOKEN_MULTIPLIER; // 1,000 quote tokens in BM
    let wallet_quote_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 quote tokens in wallet
    let wallet_base_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 base tokens in wallet

    let mut scenario = begin(OWNER);

    // Step 1: Setup fee config and loyalty program
    scenario.next_tx(OWNER);
    {
        fee::init_for_testing(scenario.ctx());
        loyalty::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup deepbook infrastructure
    let registry_id = setup_test(OWNER, &mut scenario);
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE, // Balance manager owned by ALICE
        balance_manager_quote,
        &mut scenario,
    );

    // Step 3: Create whitelisted pool (SUI/USDC)
    let pool_id = setup_pool_with_default_fees<SUI, USDC>(
        ALICE,
        registry_id,
        true, // whitelisted_pool = true
        false, // stable_pool = false
        &mut scenario,
    );

    // Step 4: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SUI>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 5: Execute the test from BOB (not the owner) - should abort
    scenario.next_tx(BOB);
    {
        let trading_fee_config = scenario.take_shared<TradingFeeConfig>();
        let loyalty_program = scenario.take_shared<LoyaltyProgram>();
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // This should abort because BOB is not the owner of the balance manager
        prepare_whitelisted_order_execution(
            &trading_fee_config,
            &loyalty_program,
            &pool,
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            order_amount,
            true, // is_bid
            scenario.ctx(),
        );

        // This line should never be reached
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
        return_shared(pool);
        return_shared(loyalty_program);
        return_shared(trading_fee_config);
    };

    scenario.end();
}
