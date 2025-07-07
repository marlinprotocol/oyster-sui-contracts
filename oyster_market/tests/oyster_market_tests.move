/*
#[test_only]
module oyster_market::oyster_market_tests;
// uncomment this line to import the module
// use oyster_market::oyster_market;

const ENotImplemented: u64 = 0;

#[test]
fun test_oyster_market() {
    // pass
}

#[test, expected_failure(abort_code = ::oyster_market::oyster_market_tests::ENotImplemented)]
fun test_oyster_market_fail() {
    abort ENotImplemented
}
*/

#[test_only]
module oyster_market::oyster_market_tests {
    use sui::tx_context::{Self, TxContext};
    use sui::object;
    use sui::table;
    use std::string;
    use std::vector;
    use oyster_market::market::{Self, MarketConfig, Marketplace, Job};
    use sui::test_scenario;
    use sui::config;
    use std::unit_test::assert_eq;
    use std::debug::print;
    use sui::object::id_from_address;
    use oyster_credits::credit_token::{Self, CreditConfig};
    use usdc::usdc::USDC;
    use sui::coin::Coin;
    use oyster_credits::credit_token::CREDIT_TOKEN;
    use sui::clock;
    use sui::coin::mint_for_testing;
    use sui::coin;
    use usdc::usdc;
    use std::u64;
    use std::u128;

    #[test]
    fun test_initialize() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);
        // let admin = test_scenario::create_signer(&scenario);
        // let mut ctx = test_scenario::ctx_with_sender(&scenario, admin);

        let notice_period_ms = 1000;
        {
            // Initialize the market config and marketplace
            market::initialize(admin, notice_period_ms, scenario.ctx());
            // print(&b"initialized!!!".to_string());
        };

        scenario.next_tx(admin);
        {
            let config = scenario.take_shared<MarketConfig>();
            assert_eq!(config.notice_period(), notice_period_ms);
            test_scenario::return_shared(config);
        };

        scenario.end();
    }

    #[test]
    fun test_add_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        let notice_period_ms = 1000;
        // Initialize the market config and marketplace
        market::initialize(admin, notice_period_ms, scenario.ctx());

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

        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_update_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        let notice_period_ms = 1000;
        // Initialize the market config and marketplace
        market::initialize(admin, notice_period_ms, scenario.ctx());

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

        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_remove_provider() {
        // Use test_scenario to create a test sender and context
        let admin = @0x1; // Simulate an admin address
        // Create a test scenario
        let mut scenario = test_scenario::begin(@0x1);

        let notice_period_ms = 1000;
        // Initialize the market config and marketplace
        market::initialize(admin, notice_period_ms, scenario.ctx());

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

        test_scenario::return_shared(config);
        scenario.end();
    }

    #[test]
    fun test_job_open_with_usdc() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        let notice_period_ms = 1000;
        market::initialize(admin, notice_period_ms, scenario.ctx());
        credit_token::test_oyster_credits_init(scenario.ctx());

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();
        let mut credit_config = scenario.take_shared<CreditConfig<USDC>>();

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

        // Create Option<Coin<USDC>> for initial_payment and Option<Coin<CREDIT_TOKEN>> for initial_credit
        let initial_payment: option::Option<Coin<USDC>> = option::some(usdc_coin);
        let initial_credit: option::Option<Coin<CREDIT_TOKEN>> = option::none();

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());
        let ctx = scenario.ctx();

        print(&b"Job Opening...".to_string());

        market::job_open(
            &config,
            &mut marketplace,
            &mut credit_config,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            initial_credit,
            &clock,
            ctx
        );

        let job_id = (u128::pow(2, 64) - 1) << 64;
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
                j_usdc_amount,
                j_credit_amount
            ) = market::job_data(&marketplace, job_id);

            let amount_used = calculate_amount_to_pay(rate, notice_period_ms);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_usdc_amount == usdc_amount - amount_used);
            assert!(j_credit_amount == 0);
            assert!(j_last_settled_ms >= clock.timestamp_ms() + notice_period_ms && j_last_settled_ms <= clock.timestamp_ms() + notice_period_ms + 1);
        };

        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        test_scenario::return_shared(credit_config);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    #[test]
    fun test_job_open_with_credit() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        let notice_period_ms = 1000;
        market::initialize(admin, notice_period_ms, scenario.ctx());
        credit_token::test_oyster_credits_init(scenario.ctx());

        scenario.next_tx(admin);
        let mut config = scenario.take_shared<MarketConfig>();
        let mut marketplace = scenario.take_shared<Marketplace>();
        let mut credit_config = scenario.take_shared<CreditConfig<USDC>>();

        let cp = string::utf8(b"https://provider.example.com");
        market::provider_add(&mut config, cp, scenario.ctx());

        scenario.next_tx(admin);

        // Open a job
        let metadata = string::utf8(b"Test job metadata");
        let provider_addr = admin;
        let rate = u64::pow(10, 16);

        let role_type = CREDIT_MINTER_ROLE;
        credit_token::grant_role(&mut credit_config, admin, role_type, scenario.ctx());

        // Deposit USDC into the credit config
        let usdc_amount = u64::pow(10, 9);
        let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
        credit_token::deposit_usdc(&mut credit_config, usdc_coin, scenario.ctx());

        let credit_amount = u64::pow(10, 9);
        credit_token::mint(&mut credit_config, admin, credit_amount, scenario.ctx());

        scenario.next_tx(admin);

        let credit_coin = scenario.take_from_sender<Coin<CREDIT_TOKEN>>();

        // Create Option<Coin<USDC>> for initial_payment and Option<Coin<CREDIT_TOKEN>> for initial_credit
        let initial_payment: option::Option<Coin<USDC>> = option::none();
        let initial_credit: option::Option<Coin<CREDIT_TOKEN>> = option::some(credit_coin);

        // Get clock and ctx from scenario
        let clock = clock::create_for_testing(scenario.ctx());
        let ctx = scenario.ctx();

        print(&b"Job Opening...".to_string());

        market::job_open(
            &config,
            &mut marketplace,
            &mut credit_config,
            metadata,
            provider_addr,
            rate,
            initial_payment,
            initial_credit,
            &clock,
            ctx
        );

        let job_id = (u128::pow(2, 64) - 1) << 64;
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
                j_usdc_amount,
                j_credit_amount
            ) = market::job_data(&marketplace, job_id);

            let amount_used = calculate_amount_to_pay(rate, notice_period_ms);

            assert!(j_job_id == job_id);
            assert!(j_metadata == metadata);
            assert!(j_owner == admin);
            assert!(j_provider == provider_addr);
            assert!(j_rate == rate);
            assert!(j_usdc_amount == 0);
            assert!(j_credit_amount == credit_amount - amount_used);
            assert!(j_last_settled_ms >= clock.timestamp_ms() + notice_period_ms && j_last_settled_ms <= clock.timestamp_ms() + notice_period_ms + 1);
        };

        test_scenario::return_shared(config);
        test_scenario::return_shared(marketplace);
        test_scenario::return_shared(credit_config);
        clock::destroy_for_testing(clock);
        scenario.end();
    }

    // #[test]
    // fun test_credit_transfer() {
    //     let admin = @0x1;
    //     let mut scenario = test_scenario::begin(admin);

    //     let notice_period_ms = 1000;
    //     market::initialize(admin, notice_period_ms, scenario.ctx());
    //     credit_token::test_oyster_credits_init(scenario.ctx());

    //     scenario.next_tx(admin);
    //     let mut credit_config = scenario.take_shared<CreditConfig<USDC>>();

    //     scenario.next_tx(admin);

    //     let role_type = CREDIT_MINTER_ROLE;
    //     credit_token::grant_role(&mut credit_config, admin, role_type, scenario.ctx());

    //     // Deposit USDC into the credit config
    //     let usdc_amount = u64::pow(10, 9);
    //     let usdc_coin = coin::mint_for_testing<USDC>(usdc_amount, scenario.ctx());
    //     credit_token::deposit_usdc(&mut credit_config, usdc_coin, scenario.ctx());

    //     let credit_amount = u64::pow(10, 9);
    //     credit_token::mint(&mut credit_config, admin, credit_amount, scenario.ctx());

    //     scenario.next_tx(admin);

    //     let mut credit_coin = scenario.take_from_sender<Coin<CREDIT_TOKEN>>();
    //     let credit_coin_to_transfer = coin::split(&mut credit_coin, 10, scenario.ctx());

    //     test_scenario::return_to_address(admin, credit_coin);

    //     scenario.next_tx(admin);

    //     let recipient = @0x2; // Simulate a recipient address
    //     //transfer credit to recipient
    //     transfer::public_transfer(credit_coin_to_transfer, recipient);

    //     scenario.next_tx(admin);
    //     // get admin credit balance
    //     let admin_credit_coin = scenario.take_from_sender<Coin<CREDIT_TOKEN>>();
        
    //     scenario.next_tx(recipient);
    //     // get recipient credit balance
    //     let recipient_credit_coin = scenario.take_from_sender<Coin<CREDIT_TOKEN>>();

    //     print(&b"Admin Balance: ".to_string());
    //     print(&admin_credit_coin.value().to_string());
    //     print(&b"Recipient Balance: ".to_string());
    //     print(&recipient_credit_coin.value().to_string());

    //     test_scenario::return_shared(credit_config);
    //     test_scenario::return_to_address(admin, admin_credit_coin);
    //     test_scenario::return_to_address(recipient, recipient_credit_coin);
    //     scenario.end();
    // }

    const CREDIT_ADMIN_ROLE: u8 = 1; // DEFAULT_ADMIN_ROLE
    const CREDIT_MINTER_ROLE: u8 = 2;
    const CREDIT_BURNER_ROLE: u8 = 3;
    const CREDIT_TRANSFER_ALLOWED_ROLE: u8 = 4;
    const CREDIT_REDEEMER_ROLE: u8 = 5;
    const CREDIT_EMERGENCY_WITHDRAW_ROLE: u8 = 6;

    const EXTRA_DECIMALS: u8 = 12;
    public fun calculate_amount_to_pay(rate: u64, duration: u64): u64 {
        let pow = u128::pow(10, EXTRA_DECIMALS);
        let amount_used = ( (rate as u128) * (duration as u128) + (pow - 1) ) / pow;
        amount_used as u64
    }

}
