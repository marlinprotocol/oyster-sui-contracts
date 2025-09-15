#[test_only]
module oyster_market::oyster_market_tests {
    use std::string;
    use oyster_market::market::{Self, MarketConfig, Marketplace};
    use sui::test_scenario;
    use usdc::usdc::USDC;
    use sui::coin::Coin;
    use sui::clock;
    use sui::coin;
    use std::u64;
    use std::u128;
    use oyster_market::lock;
    use oyster_market::lock::LockData;
    use sui::bcs;
    use sui::hash;

    #[test]
    fun test_initialize() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);
        // let admin = test_scenario::create_signer(&scenario);
        // let mut ctx = test_scenario::ctx_with_sender(&scenario, admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            let config = scenario.take_shared<MarketConfig>();
            assert!(market::has_admin_role(&config, admin));

            let marketplace = scenario.take_shared<Marketplace>();
            assert!(market::current_job_index(&marketplace) == 0);

            test_scenario::return_shared(config);
            test_scenario::return_shared(marketplace);
        };

        test_scenario::return_shared(lock_data);
        scenario.end();
    }

    #[test]
    fun test_add_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();

        let cp = string::utf8(b"https://provider.example.com");
        scenario.next_tx(admin);
        {
            market::provider_add(&mut config, cp, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            // Check provider is added
            let provider_addr = admin;
            let mut provider_cp = market::provider_cp(&config, provider_addr);
            assert!(option::is_some(&provider_cp));
            let data = option::extract(&mut provider_cp);

            assert!(data == cp, 101);
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_update_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();

        let cp = string::utf8(b"https://provider.example.com");
        scenario.next_tx(admin);
        {
            market::provider_add(&mut config, cp, scenario.ctx());
        };

        let new_cp = string::utf8(b"https://new-provider.example.com");
        scenario.next_tx(admin);
        {
            // Update provider's cp
            market::provider_update_cp(&mut config, new_cp, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            // Check provider is added
            let provider_addr = admin;
            let mut provider_cp = market::provider_cp(&config, provider_addr);
            assert!(option::is_some(&provider_cp));
            let data = option::extract(&mut provider_cp);

            assert!(data == new_cp, 101);
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_remove_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();

        let cp = string::utf8(b"https://provider.example.com");
        scenario.next_tx(admin);
        {
            market::provider_add(&mut config, cp, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            // Remove provider
            market::provider_remove(&mut config, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            // Check provider is added
            let provider_addr = admin;
            let provider_cp = market::provider_cp(&config, provider_addr);
            assert!(option::is_none(&provider_cp));
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_job_open() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = u64::pow(10, 9);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());

        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());
        let ctx = scenario.ctx();

        market::job_open(
            &mut marketplace,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            &clock,
            ctx
        );

        // let job_id = (u128::pow(2, 64) - 1) << 64;
        let job_id = 0;
        scenario.next_tx(admin);
        {
            // Check that the job exists for the provider
            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_balance,
            ) = market::job_data(&marketplace, job_id);

            // let amount_used = calculate_amount_to_pay(rate, notice_period_ms);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_balance == usdc_amount);
            assert!(
                j_last_settled_ms >= clock.timestamp_ms() && 
                j_last_settled_ms <= clock.timestamp_ms() + 1
            );
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_settle() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = u64::pow(10, 9);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());

        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let mut clock = clock::create_for_testing(scenario.ctx());
        // let ctx = scenario.ctx();

        market::job_open(
            &mut marketplace,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;

        // settle job
        scenario.next_tx(admin);
        // Advance the clock by notice_period_ms + 10
        // clock::set_for_testing(&mut clock, clock.timestamp_ms() + 1000);
        clock::increment_for_testing(&mut clock, 1000);

        market::job_settle(
            &mut marketplace,
            job_id,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            // Check that the job is settled correctly
            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_balance
            ) = market::job_data(&marketplace, job_id);

            let amount_used = calculate_amount_to_pay(rate, 1000);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_balance == usdc_amount - amount_used);
            assert!(j_last_settled_ms >= clock.timestamp_ms() && j_last_settled_ms <= clock.timestamp_ms() + 1);
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_deposit() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = u64::pow(10, 9);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());

        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );
        let time = clock::timestamp_ms(&clock);

        // deposit more usdc
        let job_id = 0;
        let deposit_amount = u64::pow(10, 9);
        let usdc_coin = coin::mint_for_testing<USDC>(deposit_amount, scenario.ctx());
        scenario.next_tx(admin);

        let payment_to_deposit: option::Option<Coin<USDC>> = option::some(usdc_coin);

        market::job_deposit(
            &mut marketplace,
            job_id,
            payment_to_deposit,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            // Check that the job exists for the provider
            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_balance
            ) = market::job_data(&marketplace, job_id);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_balance == usdc_amount + deposit_amount);
            assert!(
                j_last_settled_ms >= time && 
                j_last_settled_ms <= time + 1
            );
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_withdraw() {
        let admin = @0x1;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);
        // Get clock and ctx from scenario
        let mut clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        clock::increment_for_testing(&mut clock, 1000);

        // withdraw usdc
        let job_id = 0;
        let withdrawal_amount = usdc(100);
        market::job_withdraw(
            &mut marketplace,
            &mut lock_data,
            job_id,
            withdrawal_amount,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            // Check that the job exists for the provider
            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_balance
            ) = market::job_data(&marketplace, job_id);

            let amount_used = calculate_amount_to_pay(rate, 1000);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider);
            assert!(j_rate == rate);
            assert!(j_balance == usdc_amount - amount_used - withdrawal_amount);
            assert!(
                j_last_settled_ms >= clock::timestamp_ms(&clock) && 
                j_last_settled_ms <= clock::timestamp_ms(&clock) + 1
            );

            let provider_usdc_bal = scenario.take_from_address<Coin<USDC>>(provider);
            assert!(provider_usdc_bal.value() == amount_used);

            let user_usdc_bal = scenario.take_from_address<Coin<USDC>>(admin);
            assert!(user_usdc_bal.value() == withdrawal_amount);

            test_scenario::return_to_address(provider, provider_usdc_bal);
            test_scenario::return_to_address(admin, user_usdc_bal);
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_revise_rate_initiate() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        assert!(
            lock::lock_status(
                &lock_data, &rate_lock_selector, &job_id_bytes(job_id), &clock
            ) == STATUS_LOCKED
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = market::E_ONLY_JOB_OWNER)]
    fun test_job_revise_rate_initiate_without_job_owner() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(provider);

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_revise_rate_cancel() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);

        market::job_revise_rate_cancel(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );
        scenario.next_tx(admin);

        assert!(
            lock::lock_status(
                &lock_data, &rate_lock_selector, &job_id_bytes(job_id), &clock
            ) == STATUS_NONE
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = market::E_ONLY_JOB_OWNER)]
    fun test_job_revise_rate_cancel_without_job_owner() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(provider);

        market::job_revise_rate_cancel(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = market::E_JOB_NO_REQUEST)]
    fun test_job_revise_rate_cancel_without_initiate() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );
        scenario.next_tx(admin);

        let job_id = 0;
        market::job_revise_rate_cancel(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_revise_rate_finalize() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let mut clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        clock::increment_for_testing(&mut clock, 1100);

        market::job_revise_rate_finalize(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );
        scenario.next_tx(admin);

        {
            assert!(
                lock::lock_status(
                    &lock_data, &rate_lock_selector, &job_id_bytes(job_id), &clock
                ) == STATUS_NONE
            );

            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_balance
            ) = market::job_data(&marketplace, job_id);

            let amount_used = calculate_amount_to_pay(rate, 1100);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider);
            assert!(j_rate == new_rate);
            assert!(j_balance == usdc_amount - amount_used);
            assert!(
                j_last_settled_ms >= clock::timestamp_ms(&clock) && 
                j_last_settled_ms <= clock::timestamp_ms(&clock) + 1
            );

            let provider_usdc_bal = scenario.take_from_address<Coin<USDC>>(provider);
            assert!(provider_usdc_bal.value() == amount_used);

            test_scenario::return_to_address(provider, provider_usdc_bal);
        };


        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = market::E_ONLY_JOB_OWNER)]
    fun test_job_revise_rate_finalize_without_job_owner() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(provider);

        market::job_revise_rate_finalize(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = lock::E_LOCK_SHOULD_BE_UNLOCKED)]
    fun test_job_revise_rate_finalize_before_unlock() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);

        market::job_revise_rate_finalize(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun test_job_revise_rate_finalize_for_invalid_job() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let mut job_id = 0;
        let new_rate = rate * 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);

        // trying to finalize for non-existing job id
        job_id = 1;
        market::job_revise_rate_finalize(
            &mut marketplace, &mut lock_data, job_id, &clock, scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_close() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let mut clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = 0;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        // go past the lock wait time to unlock the rate lock
        clock::increment_for_testing(&mut clock, 1100);
        scenario.next_tx(admin);

        market::job_close(
            &mut marketplace,
            &mut lock_data,
            job_id,
            &clock,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            let job_exists = market::job_exists(&marketplace, job_id);
            assert!(!job_exists);

            let amount_used = calculate_amount_to_pay(rate, 1100);

            let provider_bal = scenario.take_from_address<Coin<USDC>>(provider);
            assert!(provider_bal.value() == amount_used);

            let admin_usdc_bal = scenario.take_from_address<Coin<USDC>>(admin);
            assert!(admin_usdc_bal.value() == usdc_amount - amount_used);

            test_scenario::return_to_address(provider, provider_bal);
            test_scenario::return_to_address(admin, admin_usdc_bal);
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = lock::E_LOCK_SHOULD_BE_UNLOCKED)]
    fun test_job_close_without_lock() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );
        scenario.next_tx(admin);

        let job_id = 0;
        market::job_close(
            &mut marketplace,
            &mut lock_data,
            job_id,
            &clock,
            scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = lock::E_LOCK_SHOULD_BE_UNLOCKED)]
    fun test_job_close_when_unlock_pending() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        let job_id = 0;
        let new_rate = 0;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );
        scenario.next_tx(admin);

        market::job_close(
            &mut marketplace,
            &mut lock_data,
            job_id,
            &clock,
            scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test, expected_failure(abort_code = market::E_JOB_NON_ZERO_RATE)]
    fun test_job_close_with_non_zero_rate() {
        let admin = @0x123;
        let provider = @0x456;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        scenario.next_tx(provider);
        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        // let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let mut clock = clock::create_for_testing(scenario.ctx());

        market::job_open(
            &mut marketplace,
            metadata,
            provider,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );

        // setting non zero rate
        let job_id = 0;
        let new_rate = 10;
        market::job_revise_rate_initiate(
            &mut marketplace,
            &mut lock_data,
            job_id,
            new_rate,
            &clock,
            scenario.ctx()
        );

        // go past the lock wait time to unlock the rate lock
        clock::increment_for_testing(&mut clock, 1100);
        scenario.next_tx(admin);

        market::job_close(
            &mut marketplace,
            &mut lock_data,
            job_id,
            &clock,
            scenario.ctx()
        );

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_metadata_update() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        lock::test_lock_init(scenario.ctx());
        scenario.next_tx(admin);

        let mut lock_data = scenario.take_shared<LockData>();
        let rate_lock_selector = lock_selector(b"RATE_LOCK");
        let selectors: vector<vector<u8>> = vector[rate_lock_selector];
        let lock_wait_times = vector[1000];

        // Initialize the market config and marketplace
        market::initialize(
            &mut lock_data,
            admin,
            selectors,
            lock_wait_times,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();

        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let usdc_amount = usdc(1000);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());

        scenario.next_tx(admin);

        // Create Option<Coin<USDC>> for initial_payment
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());
        market::job_open(
            &mut marketplace,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            &clock,
            scenario.ctx()
        );
        let time = clock::timestamp_ms(&clock);

        let job_id = 0;
        let new_metadata = string::utf8(b"https://new.provider.example.com");

        market::job_metadata_update(
            &mut marketplace,
            job_id,
            new_metadata,
            scenario.ctx()
        );

        scenario.next_tx(admin);
        {
            let (
                j_job_id,
                j_metadata,
                j_owner,
                j_provider,
                j_rate,
                j_last_settled_ms,
                j_usdc_amount
            ) = market::job_data(&marketplace, job_id);

            assert!(j_job_id == job_id);
            assert!(j_metadata == new_metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_usdc_amount == usdc_amount);
            assert!(
                j_last_settled_ms >= time && 
                j_last_settled_ms <= time + 1
            );
        };

        test_scenario::return_shared(lock_data);
        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // ------------------------X---------------------------X--------------------------------X------------------------

    /// Lock status enum like Solidity. 0=None, 1=Unlocked, 2=Locked
    const STATUS_NONE: u8 = 0;
    const STATUS_UNLOCKED: u8 = 1;
    const STATUS_LOCKED: u8 = 2;

    const EXTRA_DECIMALS: u8 = 12;
    public fun calculate_amount_to_pay(rate: u64, duration: u64): u64 {
        let pow = u128::pow(10, EXTRA_DECIMALS);
        let amount_used = ( (rate as u128) * (duration as u128) + (pow - 1) ) / pow;
        amount_used as u64
    }

    public fun usdc(value: u64): u64 {
        value * u64::pow(10, 6)
    }

    public fun lock_selector(byte_data: vector<u8>): vector<u8> {
        let s = string::utf8(byte_data);        // create string
        let bytes = string::into_bytes(s);      // get vector<u8>
        sui::hash::keccak256(&bytes)                     // returns 32-byte vector<u8>
    }

    public fun job_id_bytes(job_id: u128): vector<u8> {
        let bytes = bcs::to_bytes(&job_id);
        hash::keccak256(&bytes)
    }

}
