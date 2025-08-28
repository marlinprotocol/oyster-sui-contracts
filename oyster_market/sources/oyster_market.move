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
    use usdc::usdc::USDC;
    use sui::config;
    use std::address;
    use std::u64;
    use std::u128;

    // Define the token types
    // public struct PAYMENT_TOKEN has store, copy, drop {}
    // public struct USDC_COIN_TYPE has store, copy, drop {}
    const ADMIN_ROLE: u8 = 1;
    const EMERGENCY_WITHDRAW_ROLE: u8 = 2;

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
    const E_RATE_NOT_CHANGED: u64 = 114;
    const E_ALREADY_HAS_ADMIN_ROLE: u64 = 115;
    const E_RECIPIENT_NOT_ADMIN_ROLE: u64 = 116;
    const E_ALREADY_HAS_EMERGENCY_ROLE: u64 = 117;
    const E_RECIPIENT_NOT_EMERGENCY_ROLE: u64 = 118;

    // --- Constants ---
    const EXTRA_DECIMALS: u8 = 12; // 10^12

    // --- Structs ---

    // Shared object for market-wide configuration
    public struct MarketConfig has key {
        id: UID,
        admin_members: Table<address, bool>,
        emergency_withdraw_members: Table<address, bool>,
        notice_period: u64, // in milliseconds
        providers: Table<address, Provider>,
    }

    // Shared object to act as a central registry for all jobs
    public struct Marketplace has key {
        id: UID,
        job_index: u128, // Incrementing job ID counter
        jobs: Table<u128, Job>,
    }

    // Provider information
    public struct Provider has store, copy, drop {
        cp: String, // Control Plane URL
    }

    // A Job is a distinct, owned object.
    // It holds its own balances for the two token types.
    public struct Job has key, store {
        id: UID,
        job_id: u128, // Unique job ID, derived from the marketplace's job_index
        metadata: String,
        owner: address,
        provider: address,
        rate: u64, // rate per millisecond
        last_settled_ms: u64, // timestamp in milliseconds
        // Each job is its own vault
        payment_token_balance: Balance<USDC>,
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
    public struct ProviderUpdatedWithCp has copy, drop {
        provider: address,
        new_cp: String,
    }
    public struct JobOpened has copy, drop {
        // id: ID,
        job_id: u128,
        owner: address,
        provider: address,
        metadata: String,
    }
    public struct JobClosed has copy, drop {
        job_id: u128,
    }
    public struct JobDeposited has copy, drop {
        job_id: u128,
        from: address,
        payment_token_amount: u64,
        credit_token_amount: u64,
    }
    public struct JobSettled has copy, drop {
        job_id: u128,
        provider: address,
        payment_token_amount: u64,
        credit_token_amount: u64,
        settled_until_ms: u64,
    }
    public struct JobRateRevised has copy, drop {
        job_id: u128,
        old_rate: u64,
        new_rate: u64,
    }
    public struct NoticePeriodUpdated has copy, drop {
        new_period_ms: u64,
    }
    public struct JobMetadataUpdated has copy, drop {
        job_id: u128,
        new_metadata: String
    }
    public struct JobWithdrawn has copy, drop {
        job_id: u128,
        token_name: String, // "CREDIT" or "USDC"
        to: address,
        amount: u64,
    }
    public struct RoleGranted has copy, drop {
        role: u8,
        member: address,
    }
    public struct RoleRevoked has copy, drop {
        role: u8,
        member: address,
    }

    // --- Initialization ---
    public fun initialize(admin: address, notice_period_ms: u64, ctx: &mut TxContext) {
        let mut admin_members = table::new(ctx);
        table::add(&mut admin_members, admin, true);

        let config = MarketConfig {
            id: object::new(ctx),
            admin_members,
            emergency_withdraw_members: table::new(ctx),
            notice_period: notice_period_ms,
            providers: table::new(ctx),
        };
        transfer::share_object(config);

        let marketplace = Marketplace {
            id: object::new(ctx),
            job_index: (u128::pow(2, 64) - 1) << 64,
            jobs: table::new(ctx),
        };
        transfer::share_object(marketplace);
    }
    
    // --- Admin Functions ---
    fun assert_admin(config: &MarketConfig, ctx: &TxContext) {
        assert!(table::contains(&config.admin_members, tx_context::sender(ctx)), E_NOT_ADMIN);
    }

    public entry fun add_admin_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_admin(config, ctx);
        assert!(!table::contains(&config.admin_members, member), E_ALREADY_HAS_ADMIN_ROLE);
        table::add(&mut config.admin_members, member, true);
        event::emit(RoleGranted { role: ADMIN_ROLE, member });
    }

    public entry fun remove_admin_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_admin(config, ctx);
        assert!(table::contains(&config.admin_members, member), E_RECIPIENT_NOT_ADMIN_ROLE);
        table::remove(&mut config.admin_members, member);
        event::emit(RoleRevoked { role: ADMIN_ROLE, member });
    }

    fun assert_emergency_withdraw_role(config: &MarketConfig, member: address) {
        assert!(table::contains(&config.emergency_withdraw_members, member), E_RECIPIENT_NOT_EMERGENCY_ROLE);
    }

    public entry fun add_emergency_withdraw_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_admin(config, ctx);
        assert!(!table::contains(&config.emergency_withdraw_members, member), E_ALREADY_HAS_EMERGENCY_ROLE);
        table::add(&mut config.emergency_withdraw_members, member, true);
        event::emit(RoleGranted { role: EMERGENCY_WITHDRAW_ROLE, member });
    }

    public entry fun remove_emergency_withdraw_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_admin(config, ctx);
        assert!(table::contains(&config.emergency_withdraw_members, member), E_RECIPIENT_NOT_EMERGENCY_ROLE);
        table::remove(&mut config.emergency_withdraw_members, member);
        event::emit(RoleRevoked { role: EMERGENCY_WITHDRAW_ROLE, member });
    }

    public entry fun update_notice_period(config: &mut MarketConfig, new_period_ms: u64, ctx: &TxContext) {
        assert_admin(config, ctx);
        config.notice_period = new_period_ms;
        event::emit(NoticePeriodUpdated { new_period_ms });
    }
    
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
        event::emit(ProviderUpdatedWithCp { provider: provider_addr, new_cp });
    }

    // --- Job Lifecycle ---

    // Internal helper for settlement logic
    fun settle_job(
        job: &mut Job,
        credit_config: &mut CreditConfig<USDC>,
        settle_until_ms: u64,
        rate_to_use: u64,
        ctx: &mut TxContext
    ): bool {
        let last_settled_ms = job.last_settled_ms;
        if (settle_until_ms == last_settled_ms) { return true };
        assert!(settle_until_ms > last_settled_ms, E_CANNOT_SETTLE_IN_PAST);

        let usage_duration_ms = settle_until_ms - last_settled_ms;
        let pow = u128::pow(10, EXTRA_DECIMALS);
        let amount_used = ((rate_to_use as u128) * (usage_duration_ms as u128) + (pow - 1) ) / pow;
        let amount_used_u64 = amount_used as u64;

        let total_balance = balance::value(&job.payment_token_balance) + balance::value(&job.credit_token_balance);
        let settle_amount = if (amount_used_u64 < total_balance) { amount_used_u64 } else { total_balance };

        let (credit_to_settle, payment_to_settle) = calculate_token_split(
            settle_amount,
            balance::value(&job.credit_token_balance)
        );
        
        if (credit_to_settle > 0) {
            let credit_for_payment = coin::from_balance<CREDIT_TOKEN>(
                balance::split(&mut job.credit_token_balance, credit_to_settle),
                ctx
            );
            // This is the cross-contract call to the Credit module
            credit_token::redeem_and_burn<USDC>(
                credit_config,
                credit_for_payment,
                job.provider,
                credit_to_settle,
                ctx
            );
        };

        if (payment_to_settle > 0) {
            let payment_tokens = coin::from_balance(
                balance::split(&mut job.payment_token_balance, payment_to_settle),
                ctx
            );
            transfer::public_transfer(payment_tokens, job.provider);
        };

        job.last_settled_ms = settle_until_ms;
        event::emit(JobSettled { 
            job_id: job.job_id, 
            provider: job.provider, 
            payment_token_amount: payment_to_settle, 
            credit_token_amount: credit_to_settle,
            settled_until_ms: settle_until_ms
        });
        
        amount_used <= (settle_amount as u128)
    }

    public fun job_open(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        metadata: String,
        provider: address,
        rate: u64, // rate per millisecond
        initial_payment: Option<Coin<USDC>>,
        initial_credit: Option<Coin<CREDIT_TOKEN>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let owner = tx_context::sender(ctx);
        let mut payment_balance = balance::zero<USDC>();
        let mut credit_balance = balance::zero<CREDIT_TOKEN>();

        if (option::is_some(&initial_payment)) {
            balance::join(
                &mut payment_balance,
                coin::into_balance(option::destroy_some(initial_payment))
            );
        } else {
            option::destroy_none(initial_payment);
        };
        if (option::is_some(&initial_credit)) {
            balance::join(
                &mut credit_balance,
                coin::into_balance(option::destroy_some(initial_credit))
            );
        } else {
            option::destroy_none(initial_credit);
        };

        let job = Job {
            id: object::new(ctx),
            job_id: marketplace.job_index,
            metadata,
            owner,
            provider,
            rate: 0,
            last_settled_ms: clock::timestamp_ms(clock),
            payment_token_balance: payment_balance,
            credit_token_balance: credit_balance,
        };

        let job_id = marketplace.job_index;
        marketplace.job_index = job_id + 1;

        event::emit(JobOpened { job_id, owner, provider, metadata: job.metadata });
        table::add(&mut marketplace.jobs, job_id, job);

        revise_job_rate(config, marketplace, credit_config, job_id, rate, clock, ctx)
    }
    
    public entry fun job_settle(
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let rate = job.rate;
        settle_job(job, credit_config, clock::timestamp_ms(clock), rate, ctx);
    }
    
    public entry fun job_close(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        
        // Settle up to now + notice period
        let settle_until = clock::timestamp_ms(clock) + config.notice_period;
        let rate = job.rate;
        settle_job(job, credit_config, settle_until, rate, ctx);
        
        // Take the now-mutated job out of the table to close it
        let mut closed_job = table::remove(&mut marketplace.jobs, job_id);
        let owner = closed_job.owner;

        // Refund remaining balances
        let remaining_payment_balance = balance::value(&closed_job.payment_token_balance);
        if (remaining_payment_balance > 0) {
            transfer::public_transfer(
                coin::from_balance(
                    balance::split(&mut closed_job.payment_token_balance, remaining_payment_balance),
                    ctx
                ),
                owner
            );
        };

        let remaining_credit_balance = balance::value(&closed_job.credit_token_balance);
        if (remaining_credit_balance > 0) {
            transfer::public_transfer(
                coin::from_balance(
                    balance::split(&mut closed_job.credit_token_balance, remaining_credit_balance),
                    ctx
                ),
                owner
            );
        };

        event::emit(JobClosed { job_id });
        let Job {
            id,
            job_id: _,
            metadata:_,
            owner:_,
            provider:_,
            rate:_,
            last_settled_ms:_,
            payment_token_balance,
            credit_token_balance
        } = closed_job;
        balance::destroy_zero(payment_token_balance);
        balance::destroy_zero(credit_token_balance);
        object::delete(id);
    }

    public fun job_deposit(
        marketplace: &mut Marketplace,
        job_id: u128,
        payment_to_deposit: Option<Coin<USDC>>,
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
        event::emit(JobDeposited {
            job_id,
            from: sender,
            payment_token_amount: payment_amount,
            credit_token_amount: credit_amount
        });
    }

    public entry fun job_withdraw(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        job_id: u128,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        
        // Settle before withdrawal to ensure balances are up-to-date
        let settle_until = clock::timestamp_ms(clock) + config.notice_period;
        let rate = job.rate;
        assert!(
            settle_job(job, credit_config, settle_until, rate, ctx),
            E_INSUFFICIENT_FUNDS_FOR_SETTLEMENT
        );
        
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
            let payment_coin = coin::from_balance(
                balance::split(&mut job.payment_token_balance, payment_to_withdraw),
                ctx
            );
            transfer::public_transfer(payment_coin, job.owner);
        };
        if (credit_to_withdraw > 0) {
            let credit_coin = coin::from_balance(
                balance::split(&mut job.credit_token_balance, credit_to_withdraw),
                ctx
            );
            transfer::public_transfer(credit_coin, job.owner);
        };
    }
    
    // Internal helper to get the maximum of two numbers
    fun max(a: u64, b: u64): u64 {
        if (a > b) { a } else { b }
    }

    fun revise_job_rate(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        job_id: u128,
        new_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        
        // 1. Permission and sanity checks
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        assert!(new_rate > 0, E_INVALID_RATE);
        assert!(job.rate != new_rate, E_RATE_NOT_CHANGED);

        let current_time_ms = clock::timestamp_ms(clock);

        // 2. Settle outstanding usage up to now with the OLD rate
        if (current_time_ms > job.last_settled_ms) {
            let rate = job.rate;
            assert!(
                settle_job(job, credit_config, current_time_ms, rate, ctx),
                E_INSUFFICIENT_FUNDS_FOR_SETTLEMENT
            );
        };

        // 3. Update the rate in the job state
        let old_rate = job.rate;
        job.rate = new_rate;
        event::emit(JobRateRevised { job_id, old_rate, new_rate });

        // 4. Settle the notice period cost with the HIGHER of the two rates
        let higher_rate = max(old_rate, new_rate);
        let settle_until_ms = current_time_ms + config.notice_period;

        assert!(
            settle_job(job, credit_config, settle_until_ms, higher_rate, ctx),
            E_INSUFFICIENT_FUNDS_FOR_SETTLEMENT
        );
    }

    /**
     * @notice Revises the rate of the job.
     * @dev    First, settles any outstanding usage up to the current moment using the old rate.
     * Then, pre-pays for the notice period using the *higher* of the old and new rates.
     * @param  job_id    The ID of the job to revise.
     * @param  new_rate  The new rate for the job (per millisecond).
    */
    public entry fun job_revise_rate(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        job_id: u128,
        new_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        revise_job_rate(config, marketplace, credit_config, job_id, new_rate, clock, ctx)
    }

    /**
     * @notice Updates the metadata of the job.
     * @dev    Reverts if the new metadata is the same as the old metadata.
     * Only the job owner can call this function.
     * @param  job_id          The ID of the job to update.
     * @param  new_metadata    The new metadata string for the job.
    */
    public entry fun job_metadata_update(
        marketplace: &mut Marketplace,
        job_id: u128,
        new_metadata: String,
        ctx: &TxContext,
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);

        // Check that the caller is the owner of the job.
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);

        // Verify that the metadata has actually changed to prevent redundant updates.
        assert!(job.metadata != new_metadata, E_METADATA_NOT_CHANGED);

        job.metadata = new_metadata;

        event::emit(JobMetadataUpdated {
            job_id,
            new_metadata: job.metadata // Pass the new value to the event
        });
    }

    /**
     * @notice Allows an admin to force-settle jobs and withdraw all credit balances.
     * @dev    For each specified job, this function first settles it to `now + noticePeriod`.
     * It then withdraws the *entire remaining* credit token balance to a designated recipient
     * who must have the `EMERGENCY_WITHDRAW_ROLE`.
     * @param to       The address to receive the withdrawn credit tokens.
     * @param job_ids  A vector of job IDs to process.
    */
    public entry fun emergency_withdraw_credit(
        config: &MarketConfig,
        marketplace: &mut Marketplace,
        credit_config: &mut CreditConfig<USDC>,
        to: address,
        job_ids: vector<u128>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        // 1. Verify the caller is an admin of the market contract.
        assert_admin(config, ctx);

        // 2. Verify the recipient is authorized to receive emergency withdrawals.
        assert_emergency_withdraw_role(config, to);

        // 3. Calculate the settlement timestamp.
        let settle_until_ms = clock::timestamp_ms(clock) + config.notice_period;

        // 4. Loop through all specified job IDs and process them.
        let mut i = 0;
        let len = vector::length(&job_ids);
        while (i < len) {
            let job_id = vector::borrow(&job_ids, i);
            let job = table::borrow_mut(&mut marketplace.jobs, *job_id);

            // 5. Settle the job. We don't need to assert success, as we want to
            // withdraw funds even if the settlement fails due to insufficient balance.
            let rate = job.rate;
            settle_job(job, credit_config, settle_until_ms, rate, ctx);

            // 6. Withdraw the ENTIRE remaining credit balance from the job.
            let credit_balance = balance::value(&job.credit_token_balance);
            if (credit_balance > 0) {
                // Take the whole balance object and replace it with a new zero-balance one.
                let credit_to_withdraw = coin::from_balance(
                    balance::split(&mut job.credit_token_balance, credit_balance),
                    ctx
                );

                // Transfer the withdrawn coins to the emergency recipient.
                transfer::public_transfer(credit_to_withdraw, to);

                event::emit(JobWithdrawn {
                    job_id: *job_id,
                    token_name: string::utf8(b"CREDIT"), // Identifying the token type
                    to,
                    amount: credit_balance,
                });
            };
            i = i + 1;
        };
    }

    // --- Internal Math Helpers ---
    fun calculate_token_split(total_amount: u64, credit_balance: u64): (u64, u64) {
        if (total_amount > credit_balance) {
            (credit_balance, total_amount - credit_balance) // (creditAmount, tokenAmount)
        } else {
            (total_amount, 0)
        }
    }

    // --- Tests ---
    #[test_only]
    public fun notice_period(config: &MarketConfig): u64 {
        config.notice_period
    }

    #[test_only]
    public fun provider_cp(config: &MarketConfig, provider_addr: address): Option<String> {
        if(table::contains(&config.providers, provider_addr)) {
            let provider = table::borrow(&config.providers, provider_addr);
            // let provider = *provider_ref;
            option::some(provider.cp)
        } else {
            option::none<String>()
        }
    }

    #[test_only]
    public fun job_data(marketplace: &Marketplace, job_id: u128): (
        u128, String, address, address, u64, u64, u64, u64
    ) {
        let job = table::borrow(&marketplace.jobs, job_id);
        (
            job.job_id,
            job.metadata,
            job.owner,
            job.provider,
            job.rate,
            job.last_settled_ms,
            job.payment_token_balance.value(),
            job.credit_token_balance.value()
        )
    }

    #[test_only]
    public fun job_exists(marketplace: &Marketplace, job_id: u128): bool {
        table::contains(&marketplace.jobs, job_id)
    }

}
