module oyster_market::market {
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use std::string::{Self, String};

    use usdc::usdc::USDC;
    use std::u128;

    use oyster_market::lock;
    use sui::bcs;
    use sui::hash;

    const VERSION: u64 = 1;

    const ADMIN_ROLE: u8 = 1;

    // --- Error Constants ---
    const E_NOT_ADMIN: u64 = 101;
    const E_PROVIDER_ALREADY_EXISTS: u64 = 102;
    const E_PROVIDER_NOT_FOUND: u64 = 103;
    const E_INVALID_PROVIDER_CP: u64 = 104;
    const E_ONLY_JOB_OWNER: u64 = 105;
    const E_INVALID_AMOUNT: u64 = 106;
    const E_METADATA_NOT_CHANGED: u64 = 107;
    const E_WITHDRAWAL_EXCEEDS_JOB_BALANCE: u64 = 108;
    const E_ALREADY_HAS_ADMIN_ROLE: u64 = 109;
    const E_RECIPIENT_NOT_ADMIN_ROLE: u64 = 110;
    const E_JOB_NON_ZERO_RATE: u64 = 111;
    const E_JOB_NO_REQUEST: u64 = 112;
    const E_ALREADY_INITIALIZED: u64 = 113;
    const E_WRONG_VERSION: u64 = 114;
    const E_NOT_UPGRADE: u64 = 115;

    // --- Constants ---
    const EXTRA_DECIMALS: u8 = 12; // 10^12

    // --- Structs ---

    // Shared object for market-wide configuration
    public struct MarketConfig has key {
        id: UID,
        version: u64,
        initialized: bool,
        admin_members: Table<address, bool>,
        providers: Table<address, Provider>,
    }

    // Shared object to act as a central registry for all jobs
    public struct Marketplace has key {
        id: UID,
        version: u64,
        job_index: u128, // Incrementing job ID counter
        jobs: Table<u128, Job>,
    }

    // Provider information
    public struct Provider has store, copy, drop {
        cp: String, // Control Plane URL
    }

    // A Job is a distinct, owned object.
    // It holds its own balance for the given token type.
    public struct Job has key, store {
        id: UID,
        job_id: u128, // Unique job ID, derived from the marketplace's job_index
        metadata: String,
        owner: address,
        provider: address,
        rate: u64, // rate per second
        last_settled: u64, // timestamp in seconds
        // Each job is its own vault
        balance: Balance<USDC>
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
        job_id: u128,
        owner: address,
        provider: address,
        metadata: String,
        rate: u64,
        balance: u64,
        timestamp: u64
    }
    public struct JobClosed has copy, drop {
        job_id: u128,
    }
    public struct JobDeposited has copy, drop {
        job_id: u128,
        from: address,
        amount: u64,
    }
    public struct JobWithdrew has copy, drop {
        job_id: u128,
        to: address,
        amount: u64,
    }
    public struct JobSettled has copy, drop {
        job_id: u128,
        amount: u64,
        settled_until: u64,
    }
    public struct JobMetadataUpdated has copy, drop {
        job_id: u128,
        new_metadata: String
    }
    public struct JobReviseRateInitiated has copy, drop {
        job_id: u128,
        new_rate: u64,
    }
    public struct JobReviseRateCancelled has copy, drop {
        job_id: u128,
    }
    public struct JobReviseRateFinalized has copy, drop {
        job_id: u128,
        new_rate: u64,
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
    fun init(ctx: &mut TxContext) {
        let config = MarketConfig {
            id: object::new(ctx),
            version: VERSION,
            initialized: false,
            admin_members: table::new(ctx),
            providers: table::new(ctx),
        };
        transfer::share_object(config);

        let marketplace = Marketplace {
            id: object::new(ctx),
            version: VERSION,
            job_index: 0,
            jobs: table::new(ctx),
        };
        transfer::share_object(marketplace);
    }

    public fun initialize(
        config: &mut MarketConfig,
        lock_data: &mut lock::LockData,
        admin: address,
        selectors: vector<vector<u8>>,
        lock_wait_times: vector<u64>
    ) {
        assert!(!config.initialized, E_ALREADY_INITIALIZED);
        config.initialized = true;

        table::add(&mut config.admin_members, admin, true);
        
        lock::update_lock_wait_times(
            lock_data,
            selectors,
            lock_wait_times
        );
    }

    fun assert_version(obj_version: u64) {
        assert!(obj_version == VERSION, E_WRONG_VERSION);
    }
    
    // --- Admin Functions ---
    fun assert_admin(config: &MarketConfig, ctx: &TxContext) {
        assert!(table::contains(&config.admin_members, tx_context::sender(ctx)), E_NOT_ADMIN);
    }

    public fun add_admin_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_version(config.version);
        assert_admin(config, ctx);
        assert!(!table::contains(&config.admin_members, member), E_ALREADY_HAS_ADMIN_ROLE);
        table::add(&mut config.admin_members, member, true);
        event::emit(RoleGranted { role: ADMIN_ROLE, member });
    }

    public fun remove_admin_member(config: &mut MarketConfig, member: address, ctx: &TxContext) {
        assert_version(config.version);
        assert_admin(config, ctx);
        assert!(table::contains(&config.admin_members, member), E_RECIPIENT_NOT_ADMIN_ROLE);
        table::remove(&mut config.admin_members, member);
        event::emit(RoleRevoked { role: ADMIN_ROLE, member });
    }
    
    // --- Provider Management ---
    public fun provider_add(config: &mut MarketConfig, cp: String, ctx: &mut TxContext) {
        assert_version(config.version);
        let provider_addr = tx_context::sender(ctx);
        assert!(!table::contains(&config.providers, provider_addr), E_PROVIDER_ALREADY_EXISTS);
        assert!(string::length(&cp) > 0, E_INVALID_PROVIDER_CP);
        
        table::add(&mut config.providers, provider_addr, Provider { cp });
        event::emit(ProviderAdded { provider: provider_addr, cp });
    }
    
    public fun provider_remove(config: &mut MarketConfig, ctx: &mut TxContext) {
        assert_version(config.version);
        let provider_addr = tx_context::sender(ctx);
        assert!(table::contains(&config.providers, provider_addr), E_PROVIDER_NOT_FOUND);
        
        let Provider { cp: _ } = table::remove(&mut config.providers, provider_addr);
        event::emit(ProviderRemoved { provider: provider_addr });
    }

    public fun provider_update_cp(config: &mut MarketConfig, new_cp: String, ctx: &TxContext) {
        assert_version(config.version);
        let provider_addr = tx_context::sender(ctx);
        assert!(string::length(&new_cp) > 0, E_INVALID_PROVIDER_CP);
        let provider = table::borrow_mut(&mut config.providers, provider_addr);
        provider.cp = new_cp;
        event::emit(ProviderUpdatedWithCp { provider: provider_addr, new_cp });
    }

    // --- Job Lifecycle ---

    // --- Job internal funtions ---
    fun job_id_bytes(job_id: u128): vector<u8> {
        let bytes = bcs::to_bytes(&job_id);
        hash::keccak256(&bytes)
    }

    fun deposit(
        job: &mut Job,
        payment_to_deposit: Coin<USDC>
    ): u64 {
        let payment_amount = coin::value(&payment_to_deposit);
        balance::join(&mut job.balance, coin::into_balance(payment_to_deposit));

        return payment_amount
    }

    fun withdraw(
        job: &mut Job,
        to: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        if (amount > 0) {
            let payment_tokens = coin::from_balance(
                balance::split(&mut job.balance, amount),
                ctx
            );
            transfer::public_transfer(payment_tokens, to);
        };
    }

    fun settle_job(
        job: &mut Job,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock) / 1000;

        let usage_duration = current_time - job.last_settled;
        let pow = u128::pow(10, EXTRA_DECIMALS);
        let amount_used_u128 = ((job.rate as u128) * (usage_duration as u128) + (pow - 1) ) / pow;
        let mut amount_used = amount_used_u128 as u64;

        let balance = balance::value(&job.balance);
        if (amount_used > balance) {
            amount_used = balance;
        };

        let to = job.provider;
        withdraw(job, to, amount_used, ctx);

        job.last_settled = current_time;
        event::emit(JobSettled { 
            job_id: job.job_id,
            amount: amount_used,
            settled_until: current_time
        });
    }

    fun job_close_internal(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        settle_job(job, clock, ctx);

        let balance = balance::value(&job.balance);
        if (balance > 0) {
            let to = job.owner;
            withdraw(job, to, balance, ctx);
        };

        let closed_job = table::remove(&mut marketplace.jobs, job_id);
        let Job {
            id,
            job_id: _,
            metadata:_,
            owner:_,
            provider:_,
            rate:_,
            last_settled:_,
            balance,
        } = closed_job;
        balance::destroy_zero(balance);
        object::delete(id);

        lock::revert_lock(lock_data, rate_lock_selector(), job_id_bytes(job_id));

        event::emit(JobClosed { job_id });
    }

    fun revise_job_rate(
        job: &mut Job,
        job_id: u128,
        new_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        settle_job(job, clock, ctx);

        job.rate = new_rate;
        event::emit(JobReviseRateFinalized { job_id, new_rate });
    }

    // --- Job public functions ---
    public fun job_open(
        marketplace: &mut Marketplace,
        metadata: String,
        provider: address,
        rate: u64, // rate per second
        initial_payment: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_version(marketplace.version);
        let owner = tx_context::sender(ctx);
        let payment_balance = balance::zero<USDC>();
        let job_id = marketplace.job_index;
        let current_time = clock::timestamp_ms(clock) / 1000;

        let job = Job {
            id: object::new(ctx),
            job_id: marketplace.job_index,
            metadata,
            owner,
            provider,
            rate,
            last_settled: current_time,
            balance: payment_balance
        };

        marketplace.job_index = job_id + 1;

        table::add(&mut marketplace.jobs, job_id, job);

        let balance = deposit(
            marketplace.jobs.borrow_mut(job_id),
            initial_payment
        );

        event::emit(JobOpened {
            job_id,
            owner,
            provider,
            metadata,
            rate,
            balance,
            timestamp: current_time
        });
    }
    
    public fun job_settle(
        marketplace: &mut Marketplace,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        settle_job(job, clock, ctx);
    }
    
    public fun job_close(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        assert!(job.owner == tx_context::sender(ctx), E_ONLY_JOB_OWNER);
        
        // 0 rate jobs can be closed without notice
        if(job.rate == 0) {
            job_close_internal(
                marketplace,
                lock_data,
                job_id,
                clock,
                ctx
            );
        };

        // non-0 rate jobs can be closed after proper notice
        let new_rate = lock::unlock(
            lock_data, rate_lock_selector(), job_id_bytes(job_id), clock
        );
        assert!(new_rate == 0, E_JOB_NON_ZERO_RATE);

        job_close_internal(
            marketplace,
            lock_data,
            job_id,
            clock,
            ctx
        );
    }

    public fun job_deposit(
        marketplace: &mut Marketplace,
        job_id: u128,
        payment_to_deposit: Coin<USDC>,
        ctx: &mut TxContext,
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);

        let amount = deposit(job, payment_to_deposit);
        event::emit(JobDeposited {
            job_id: job.job_id,
            from: tx_context::sender(ctx),
            amount: amount
        });
    }

    public fun job_withdraw(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert_version(marketplace.version);
        assert!(amount > 0, E_INVALID_AMOUNT);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let sender = tx_context::sender(ctx);
        assert!(job.owner == sender, E_ONLY_JOB_OWNER);
        
        // Settle before withdrawal to ensure balances are up-to-date
        settle_job(job, clock, ctx);

        let lock_wait_time = lock::lock_wait_time(lock_data, rate_lock_selector());
        let pow = u128::pow(10, EXTRA_DECIMALS);
        let leftover_u128 = ((job.rate as u128) * (lock_wait_time as u128) + (pow - 1)) / pow;
        let leftover = leftover_u128 as u64;

        let balance = balance::value(&job.balance);
        assert!(balance >= leftover, E_WITHDRAWAL_EXCEEDS_JOB_BALANCE);

        let max_withdrawable = balance - leftover;
        assert!(amount <= max_withdrawable, E_WITHDRAWAL_EXCEEDS_JOB_BALANCE);

        withdraw(job, sender, amount, ctx);

        event::emit(JobWithdrew {
            job_id: job.job_id,
            to: sender,
            amount,
        });
    }

    public fun job_revise_rate_initiate(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        new_rate: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let sender = tx_context::sender(ctx);
        assert!(job.owner == sender, E_ONLY_JOB_OWNER);

        lock::lock(
            lock_data,
            rate_lock_selector(),
            job_id_bytes(job_id),
            new_rate as u256,
            clock
        );

        event::emit(JobReviseRateInitiated { job_id, new_rate });
    }

    public fun job_revise_rate_cancel(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let sender = tx_context::sender(ctx);
        assert!(job.owner == sender, E_ONLY_JOB_OWNER);

        let selector = rate_lock_selector();
        let key = job_id_bytes(job_id);
        assert!(
            lock::lock_status(lock_data, &selector, &key, clock) != lock::lock_status_none(),
            E_JOB_NO_REQUEST
        );

        lock::revert_lock(lock_data, selector, key);

        event::emit(JobReviseRateCancelled { job_id });
    }

    public fun job_revise_rate_finalize(
        marketplace: &mut Marketplace,
        lock_data: &mut lock::LockData,
        job_id: u128,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert_version(marketplace.version);
        let job = table::borrow_mut(&mut marketplace.jobs, job_id);
        let sender = tx_context::sender(ctx);
        assert!(job.owner == sender, E_ONLY_JOB_OWNER);

        let selector = rate_lock_selector();
        let key = job_id_bytes(job_id);
        let new_rate = lock::unlock(lock_data, selector, key, clock);

        revise_job_rate(job, job_id, new_rate as u64, clock, ctx);
    }

    /**
     * @notice Updates the metadata of the job.
     * @dev    Reverts if the new metadata is the same as the old metadata.
     * Only the job owner can call this function.
     * @param  job_id          The ID of the job to update.
     * @param  new_metadata    The new metadata string for the job.
    */
    public fun job_metadata_update(
        marketplace: &mut Marketplace,
        job_id: u128,
        new_metadata: String,
        ctx: &TxContext,
    ) {
        assert_version(marketplace.version);
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

    // // to be called when the package is upgraded
    // entry fun migrate(
    //     config: &mut MarketConfig,
    //     marketplace: &mut Marketplace,
    //     lock_data: &mut lock::LockData,
    //     ctx: &TxContext
    // ) {
    //     assert_admin(config, ctx);
    //     assert!(config.version < VERSION, E_NOT_UPGRADE);
    //     assert!(marketplace.version < VERSION, E_NOT_UPGRADE);

    //     config.version = VERSION;
    //     marketplace.version = VERSION;

    //     lock::migrate(lock_data);
    // }

    public fun rate_lock_selector(): vector<u8> {
        let s = string::utf8(b"RATE_LOCK");      // create string
        let bytes = string::into_bytes(s);       // get vector<u8>
        sui::hash::keccak256(&bytes)                      // returns 32-byte vector<u8>
    }

    public fun provider_cp(config: &MarketConfig, provider_addr: address): Option<String> {
        if(table::contains(&config.providers, provider_addr)) {
            let provider = table::borrow(&config.providers, provider_addr);
            option::some(provider.cp)
        } else {
            option::none<String>()
        }
    }

    public fun job_data(marketplace: &Marketplace, job_id: u128): (
        u128, String, address, address, u64, u64, u64
    ) {
        let job = table::borrow(&marketplace.jobs, job_id);
        (
            job.job_id,
            job.metadata,
            job.owner,
            job.provider,
            job.rate,
            job.last_settled,
            job.balance.value()
        )
    }

    public fun job_exists(marketplace: &Marketplace, job_id: u128): bool {
        table::contains(&marketplace.jobs, job_id)
    }

    public fun has_admin_role(config: &MarketConfig, user: address): bool {
        table::contains(&config.admin_members, user)
    }

    public fun current_job_index(marketplace: &Marketplace): u128 {
        marketplace.job_index
    }

    public fun extra_decimals(): u8 {
        EXTRA_DECIMALS
    }

    // --- Tests ---
    #[test_only]
    public fun test_market_init(ctx: &mut TxContext) {
        init(ctx);
    }

}
