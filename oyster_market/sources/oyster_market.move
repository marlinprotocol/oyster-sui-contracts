/*
/// Module: oyster_market
module oyster_market::oyster_market;
*/

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

// Module: oyster_market.move
// Depends on the 'oyster_credits::credit_token' module.
// <phantom PAYMENT_TOKEN, phantom CREDIT_TOKEN, phantom USDC_COIN_TYPE>
module oyster_market::market {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::bag::{Self, Bag};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};

    // Import the Credit contract module
    use oyster_credits::credit_token::{Self, CreditConfig, CREDIT_TOKEN};

    // Define the token types
    public struct PAYMENT_TOKEN has store, copy, drop {}
    public struct USDC_COIN_TYPE has store, copy, drop {}

    // --- Error Constants ---
    const E_NOT_ADMIN: u64 = 101;
    const E_PROVIDER_ALREADY_EXISTS: u64 = 102;
    const E_PROVIDER_NOT_FOUND: u64 = 103;
    const E_INVALID_PROVIDER_CP: u64 = 104;
    const E_JOB_NOT_FOUND: u64 = 105;
    const E_ONLY_JOB_OWNER: u64 = 106;
    const E_INVALID_AMOUNT: u64 = 107;
    const E_INVALID_RATE: u64 = 108;
    const E_METADATA_NOT_CHANGED: u64 = 109;
    const E_CANNOT_SETTLE_IN_PAST: u64 = 110;
    const E_INSUFFICIENT_FUNDS_FOR_SETTLEMENT: u64 = 111;
    const E_WITHDRAWAL_EXCEEDS_JOB_BALANCE: u64 = 112;
    const E_NO_ADMIN_EXISTS: u64 = 113;

    // --- Constants ---
    const EXTRA_DECIMALS: u128 = 1_000_000_000_000; // 10^12

    // --- Structs ---

    // Shared object for market-wide configuration
    public struct MarketConfig has key {
        id: UID,
        admin_members: Bag,
        notice_period: u64, // in milliseconds
        providers: Table<address, Provider>,
    }

    // Shared object to act as a central registry for all jobs
    public struct Marketplace has key {
        id: UID,
        jobs: Table<ID, Job>,
    }

    // Provider information
    public struct Provider has store, copy, drop {
        cp: String, // Control Plane URL
    }

    // A Job is a distinct, owned object.
    // It holds its own balances for the two token types.
    public struct Job has key, store {
        id: UID,
        metadata: String,
        owner: address,
        provider: address,
        rate: u64, // rate per millisecond
        last_settled_ms: u64, // timestamp in milliseconds
        // Each job is its own vault
        payment_token_balance: Balance<PAYMENT_TOKEN>,
        credit_token_balance: Balance<CREDIT_TOKEN>,
    }

    // --- Events ---
    public struct ProviderAdded has copy, drop {
        provider: address,
        cp: String,
    }
    public struct ProviderRemoved has copy, drop {
        provider: address,
    }
    public struct JobOpened has copy, drop {
        job_id: ID,
        owner: address,
        provider: address,
        metadata: String,
    }
    public struct JobClosed has copy, drop {
        job_id: ID,
    }
    public struct JobDeposited has copy, drop {
        job_id: ID,
        from: address,
        payment_token_amount: u64,
        credit_token_amount: u64,
    }
    public struct JobSettled has copy, drop {
        job_id: ID,
        provider: address,
        payment_token_amount: u64,
        credit_token_amount: u64,
        settled_until_ms: u64,
    }
    // Add other events for Withdraw, ReviseRate etc. as needed.


    // --- Initialization ---
    public fun initialize(admin: address, notice_period_ms: u64, ctx: &mut TxContext) {
        let mut admin_bag = bag::new(ctx);
        bag::add(&mut admin_bag, admin, true);

        let config = MarketConfig {
            id: object::new(ctx),
            admin_members: admin_bag,
            notice_period: notice_period_ms,
            providers: table::new(ctx),
        };
        transfer::share_object(config);

        let marketplace = Marketplace {
            id: object::new(ctx),
            jobs: table::new(ctx),
        };
        transfer::share_object(marketplace);
    }
    
    // --- Admin Functions ---
    fun assert_admin(config: &MarketConfig, ctx: &TxContext) {
        assert!(bag::contains(&config.admin_members, tx_context::sender(ctx)), E_NOT_ADMIN);
    }

    public entry fun update_notice_period(config: &mut MarketConfig, new_period_ms: u64, ctx: &TxContext) {
        assert_admin(config, ctx);
        config.notice_period = new_period_ms;
    }
    // As mentioned, `updateToken` and `updateCreditToken` are not directly translatable
    // as token types are generic. A new module deployment would be required to change them.
    
    // --- Provider Management ---
    public entry fun provider_add(config: &mut MarketConfig, cp: String, ctx: &mut TxContext) {
        let provider_addr = tx_context::sender(ctx);
        assert!(!table::contains(&config.providers, provider_addr), E_PROVIDER_ALREADY_EXISTS);
        assert!(string::length(&cp) > 0, E_INVALID_PROVIDER_CP);
        
        table::add(&mut config.providers, provider_addr, Provider { cp });
        event::emit(ProviderAdded { provider: provider_addr, cp });
    }
    
    public entry fun provider_remove(config: &mut MarketConfig, ctx: &mut TxContext) {
        let provider_addr = tx_context::sender(ctx);
        assert!(table::contains(&config.providers, provider_addr), E_PROVIDER_NOT_FOUND);
        
        let Provider { cp: _ } = table::remove(&mut config.providers, provider_addr);
        event::emit(ProviderRemoved { provider: provider_addr });
    }

    public entry fun provider_update_cp(config: &mut MarketConfig, new_cp: String, ctx: &TxContext) {
        let provider_addr = tx_context::sender(ctx);
        assert!(string::length(&new_cp) > 0, E_INVALID_PROVIDER_CP);
        let provider = table::borrow_mut(&mut config.providers, provider_addr);
        provider.cp = new_cp;
    }

    // --- Job Lifecycle ---

    // Internal helper for settlement logic
    fun settle_job(
        job: &mut Job,
        credit_config: &mut CreditConfig<USDC_COIN_TYPE>,
        settle_until_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): bool {
        let last_settled_ms = job.last_settled_ms;
        if (settle_until_ms <= last_settled_ms) { return true };

        let usage_duration_ms = settle_until_ms - last_settled_ms;
        let amount_used = ( (job.rate as u128) * (usage_duration_ms as u128) + (EXTRA_DECIMALS - 1) ) / EXTRA_DECIMALS;
        let amount_used_u64 = amount_used as u64;

        let total_balance = balance::value(&job.payment_token_balance) + balance::value(&job.credit_token_balance);
        let settle_amount = if (amount_used_u64 < total_balance) { amount_used_u64 } else { total_balance };

        let (credit_to_settle, payment_to_settle) = calculate_token_split(settle_amount, balance::value(&job.credit_token_balance));
        
        if (credit_to_settle > 0) {
            let credit_for_payment = coin::from_balance<CREDIT_TOKEN>(balance::split(&mut job.credit_token_balance, credit_to_settle), ctx);
            // This is the cross-contract call to the Credit module
            credit_token::redeem_and_burn<USDC_COIN_TYPE>(credit_config, credit_for_payment, job.provider, credit_to_settle, ctx);
        };

        if (payment_to_settle > 0) {
            let payment_tokens = coin::from_balance(balance::split(&mut job.payment_token_balance, payment_to_settle), ctx);
            transfer::public_transfer(payment_tokens, job.provider);
        };

        job.last_settled_ms = settle_until_ms;
        event::emit(JobSettled { 
            job_id: object::id(job), 
            provider: job.provider, 
            payment_token_amount: payment_to_settle, 
            credit_token_amount: credit_to_settle,
            settled_until_ms: settle_until_ms
        });
        
        amount_used <= (settle_amount as u128)
    }

    public fun job_open(
        marketplace: &mut Marketplace,
        metadata: String,
        provider: address,
        rate: u64, // rate per millisecond
        initial_payment: Option<Coin<PAYMENT_TOKEN>>,
        initial_credit: Option<Coin<CREDIT_TOKEN>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let mut payment_balance = balance::zero<PAYMENT_TOKEN>();
        let mut credit_balance = balance::zero<CREDIT_TOKEN>();

        if (option::is_some(&initial_payment)) {
            balance::join(&mut payment_balance, coin::into_balance(option::destroy_some(initial_payment)));
        } else {
            option::destroy_none(initial_payment);
        };
        if (option::is_some(&initial_credit)) {
            balance::join(&mut credit_balance, coin::into_balance(option::destroy_some(initial_credit)));
        } else {
            option::destroy_none(initial_credit);
        };
        
        let job = Job {
            id: object::new(ctx),
            metadata,
            owner,
            provider,
            rate,
            last_settled_ms: clock::timestamp_ms(clock),
            payment_token_balance: payment_balance,
            credit_token_balance: credit_balance,
        };

        event::emit(JobOpened { job_id: object::id(&job), owner, provider, metadata: job.metadata });
        table::add(&mut marketplace.jobs, object::id(&job), job);
    }
    
    public entry fun job_settle(
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC_COIN_TYPE>,
        job_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        settle_job(job, credit_config, clock::timestamp_ms(clock), clock, ctx);
    }
    
    public entry fun job_close(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC_COIN_TYPE>,
        job_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        
        // Settle up to now + notice period
        let settle_until = clock::timestamp_ms(clock) + config.notice_period;
        settle_job(job, credit_config, settle_until, clock, ctx);
        
        // Take the now-mutated job out of the table to close it
        let mut closed_job = table::remove(&mut marketplace.jobs, job_id);
        let owner = closed_job.owner;

        // // Refund remaining balances
        // let remaining_payment_balance = balance::value(&closed_job.payment_token_balance);
        // if (remaining_payment_balance > 0) {
        //     transfer::public_transfer(coin::from_balance(closed_job.payment_token_balance, ctx), owner);
        // } else {
        //     balance::destroy_zero(closed_job.payment_token_balance);
        // };

        // let remaining_credit_balance = balance::value(&closed_job.credit_token_balance);
        // if (remaining_credit_balance > 0) {
        //     transfer::public_transfer(coin::from_balance(closed_job.credit_token_balance, ctx), owner);
        // } else {
        //     balance::destroy_zero(closed_job.credit_token_balance);
        // };

        event::emit(JobClosed { job_id });
        let Job { id, metadata:_, owner:_, provider:_, rate:_, last_settled_ms:_, payment_token_balance, credit_token_balance } = closed_job;
        balance::destroy_zero(payment_token_balance);
        balance::destroy_zero(credit_token_balance);
        object::delete(id);
    }

    public fun job_deposit(
        marketplace: &mut Marketplace,
        job_id: ID,
        payment_to_deposit: Option<Coin<PAYMENT_TOKEN>>,
        credit_to_deposit: Option<Coin<CREDIT_TOKEN>>,
        ctx: &mut TxContext,
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let sender = tx_context::sender(ctx);
        let mut payment_amount = 0;
        let mut credit_amount = 0;

        if (option::is_some(&payment_to_deposit)) {
            let coin = option::destroy_some(payment_to_deposit);
            payment_amount = coin::value(&coin);
            balance::join(&mut job.payment_token_balance, coin::into_balance(coin));
        } else {
            option::destroy_none(payment_to_deposit);
        };
        if (option::is_some(&credit_to_deposit)) {
            let coin = option::destroy_some(credit_to_deposit);
            credit_amount = coin::value(&coin);
            balance::join(&mut job.credit_token_balance, coin::into_balance(coin));
        } else {
            option::destroy_none(credit_to_deposit);
        };
        assert!(payment_amount > 0 || credit_amount > 0, E_INVALID_AMOUNT);
        event::emit(JobDeposited { job_id, from: sender, payment_token_amount: payment_amount, credit_token_amount: credit_amount });
    }

    public entry fun job_withdraw(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC_COIN_TYPE>,
        job_id: ID,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        
        // Settle before withdrawal to ensure balances are up-to-date
        let settle_until = clock::timestamp_ms(clock) + config.notice_period;
        assert!(settle_job(job, credit_config, settle_until, clock, ctx), E_INSUFFICIENT_FUNDS_FOR_SETTLEMENT);
        
        let total_balance = balance::value(&job.payment_token_balance) + balance::value(&job.credit_token_balance);
        assert!(total_balance >= amount, E_WITHDRAWAL_EXCEEDS_JOB_BALANCE);

        // Prioritize withdrawing payment_token first, then credit_token (matches Solidity `_withdraw`)
        let payment_balance = balance::value(&job.payment_token_balance);
        let (payment_to_withdraw, credit_to_withdraw) = if (amount > payment_balance) {
            (payment_balance, amount - payment_balance)
        } else {
            (amount, 0)
        };

        if (payment_to_withdraw > 0) {
            let payment_coin = coin::from_balance(balance::split(&mut job.payment_token_balance, payment_to_withdraw), ctx);
            transfer::public_transfer(payment_coin, job.owner);
        };
        if (credit_to_withdraw > 0) {
            let credit_coin = coin::from_balance(balance::split(&mut job.credit_token_balance, credit_to_withdraw), ctx);
            transfer::public_transfer(credit_coin, job.owner);
        };
    }
    
    // ... Implement `job_revise_rate` and `job_metadata_update` similarly ...
    // They would take `&mut Marketplace` and `job_id`, borrow the job, check ownership, and make changes.

    // --- Internal Math Helpers ---
    fun calculate_token_split(total_amount: u64, credit_balance: u64): (u64, u64) {
        if (total_amount > credit_balance) {
            (credit_balance, total_amount - credit_balance) // (creditAmount, tokenAmount)
        } else {
            (total_amount, 0)
        }
    }
}
