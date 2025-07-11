// Module: oyster_credits.move
// This is a conceptual translation. Publisher address needs to be set (e.g., 0x0).
module oyster_credits::credit_token {
    use sui::coin::{Self, Coin, TreasuryCap, CoinMetadata};
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, ID, UID};
    use sui::event;
    use sui::bag::{Self, Bag}; // Using Bag for role membership
    use std::option::{Self, Option, some, none};
    use std::vector;
    use std::string::{Self, String};
    use sui::table::{Self, Table};
    use usdc::usdc::USDC;

    // --- Phantom type for the Credit token ---
    // public struct CREDIT has drop {}
    // public struct USDC has drop {} // Placeholder for USDC coin type, to be replaced with actual USDC type in Sui

    // --- Error Constants ---
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_ADMIN: u64 = 2;
    const E_PAUSED: u64 = 3;
    const E_NOT_PAUSED: u64 = 4;
    const E_NOT_MINTER: u64 = 5;
    const E_NOT_BURNER: u64 = 6;
    const E_NOT_REDEEMER: u64 = 7;
    const E_SENDER_NOT_TRANSFER_ALLOWED: u64 = 8;
    const E_RECIPIENT_NOT_TRANSFER_ALLOWED: u64 = 9;
    const E_ONE_PARTY_MUST_BE_TRANSFER_ALLOWED: u64 = 10;
    const E_INSUFFICIENT_USDC_IN_CONTRACT: u64 = 11;
    const E_RECIPIENT_NOT_EMERGENCY_WITHDRAW_ROLE: u64 = 12;
    const E_NO_ADMIN_EXISTS: u64 = 13; // Cannot remove the last admin
    const E_CALLER_NOT_AUTHORIZED_FOR_UPGRADE: u64 = 14;
    const E_INVALID_ROLE: u64 = 15; // If managing roles by a numerical type
    const E_UNAUTHORIZED: u64 = 16; // General unauthorized error

    // --- Role Identifiers (could also be distinct structs/capabilities) ---
    // Using u8 for simplicity to identify roles if needed for a generic grant/revoke function.
    // However, direct Bag fields are used below for clarity.
    const ADMIN_ROLE: u8 = 1; // DEFAULT_ADMIN_ROLE
    const MINTER_ROLE: u8 = 2;
    const BURNER_ROLE: u8 = 3;
    const TRANSFER_ALLOWED_ROLE: u8 = 4;
    const REDEEMER_ROLE: u8 = 5;
    const EMERGENCY_WITHDRAW_ROLE: u8 = 6;

    // --- Main Shared Object for Configuration and State ---
    public struct CreditConfig<phantom USDC> has key {
        id: UID,
        treasury_cap: TreasuryCap<CREDIT_TOKEN>,
        is_paused: bool,
        // Role Memberships
        members: Table<u8, Table<address, bool>>,
        // admin_members: Bag,
        // minter_members: Bag,
        // burner_members: Bag,
        // transfer_allowed_members: Bag, // For _beforeTokenTransfer checks
        // redeemer_members: Bag,
        // emergency_withdraw_recipients: Bag, // Who can *receive* emergency withdrawals

        // Contract's vault for holding USDC for redemptions
        usdc_vault: Balance<USDC>,
    }

    // --- Events (Optional, for off-chain indexing) ---
    public struct RoleGranted has copy, drop {
        role: u8, // e.g., "MINTER_ROLE"
        account: address,
        granter: address,
    }
    public struct RoleRevoked has copy, drop {
        role: u8,
        account: address,
        revoker: address,
    }
    public struct Paused has copy, drop {
        pauser: address,
    }
    public struct Unpaused has copy, drop {
        unpauser: address,
    }
    public struct Minted has copy, drop {
        minter: address,
        recipient: address,
        amount: u64,
    }
    public struct Burned has copy, drop {
        burner: address,
        amount: u64,
    }
    // Add other events for Redeem, EmergencyWithdraw if needed.

    // --- One-Time Witness for Initialization ---
    public struct CREDIT_TOKEN has drop {}

    // --- Initialization ---
    fun init(witness: CREDIT_TOKEN, ctx: &mut TxContext) {
        // Create the CREDIT coin
        let (treasury_cap, metadata) = coin::create_currency<CREDIT_TOKEN>(
            witness,
            6, // Decimals (as in Solidity contract)
            b"CREDIT", // Symbol
            b"Oyster Credit", // Name
            b"Oyster Credit Token", // Description
            option::none(), // Icon URL
            ctx
        );

        // Create and share the configuration object
        let sender = tx_context::sender(ctx);
        // let mut admin_members_bag = bag::new(ctx);
        // bag::add(&mut admin_members_bag, sender, true); // Initial admin is the deployer
        let mut members = table::new(ctx);
        let mut admin_members = table::new(ctx);
        table::add(&mut admin_members, sender, true);
        table::add(&mut members, ADMIN_ROLE, admin_members);

        let config = CreditConfig<USDC> {
            id: object::new(ctx),
            treasury_cap,
            is_paused: false,
            members,
            // admin_members: admin_members_bag,
            // minter_members: bag::new(ctx),
            // burner_members: bag::new(ctx),
            // transfer_allowed_members: bag::new(ctx),
            // redeemer_members: bag::new(ctx),
            // emergency_withdraw_recipients: bag::new(ctx),
            usdc_vault: balance::zero<USDC>(),
        };
        
        // Make TreasuryCap and CoinMetadata available
        transfer::public_freeze_object(metadata); // Or a specific admin address
        // The CreditConfig is the main shared object; TreasuryCap is within it.
        transfer::share_object(config);
    }

    // // --- Internal Helper: Role Check ---
    // fun has_role(bag: &Bag, account: address): bool {
    //     bag::contains(bag, account)
    // }

    // --- Internal Helper: Admin Check ---
    // fun assert_admin<USDC>(config: &CreditConfig<USDC>, ctx: &TxContext) {
    //     assert!(has_role(&config.admin_members, tx_context::sender(ctx)), E_NOT_ADMIN);
    // }

    // --- Internal Helper: Paused Check ---
    fun assert_not_paused<USDC>(config: &CreditConfig<USDC>) {
        assert!(!config.is_paused, E_PAUSED);
    }

    public fun has_role(config: &mut CreditConfig<USDC>, account: address, role_type: u8): bool {
        if (table::contains(&config.members, role_type)) {
            let role_set = table::borrow(&config.members, role_type);
            table::contains(role_set, account)
        } else {
            false
        }
    }

    // `assert_has_role` has no changes, as it just calls `has_role`.
    public fun assert_has_role(config: &mut CreditConfig<USDC>, account: address, role_type: u8) {
        assert!(has_role(config, account, role_type), E_UNAUTHORIZED);
    }

    // --- Role Management Functions (callable by Admin) ---
    // Example for MINTER_ROLE. Similar functions for other roles.
    // public entry fun grant_minter_role<USDC>(
    //     config: &mut CreditConfig<USDC>,
    //     account: address,
    //     ctx: &TxContext
    // ) {
    //     assert_admin(config, ctx);
    //     bag::add(&mut config.minter_members, account, true);
    //     event::emit(RoleGranted {
    //         role_name: string::utf8(b"MINTER_ROLE"),
    //         account: account,
    //         granter: tx_context::sender(ctx),
    //     });
    // }

    // `grant_role` is updated to use Table logic.
    public fun grant_role(config: &mut CreditConfig<USDC>, account: address, role_type: u8, ctx: &mut TxContext) {
        assert_has_role(config, tx_context::sender(ctx), ADMIN_ROLE);

        // If this is the first time, create a new inner Table for the role.
        if (!table::contains(&config.members, role_type)) {
            table::add(&mut config.members, role_type, table::new(ctx));
        };

        let role_set = table::borrow_mut(&mut config.members, role_type);
        // Add the member address as the key and `true` as the value.
        table::add(role_set, account, true);

        event::emit(RoleGranted { role: role_type, account, granter: tx_context::sender(ctx) });
    }

    public fun revoke_role(config: &mut CreditConfig<USDC>, account: address, role_type: u8, ctx: &mut TxContext) {
        assert_has_role(config, tx_context::sender(ctx), ADMIN_ROLE);

        if (table::contains(&config.members, role_type)) {
            let role_set = table::borrow_mut(&mut config.members, role_type);
            if (table::contains(role_set, account)) {
                 let _ = table::remove(role_set, account);
                 event::emit(RoleRevoked { role: role_type, account, revoker: tx_context::sender(ctx) });
            }
        }
    }

    // public entry fun revoke_minter_role<USDC>(
    //     config: &mut CreditConfig<USDC>,
    //     account: address,
    //     ctx: &TxContext
    // ) {
    //     assert_admin(config, ctx);
    //     bag::remove<address, bool>(&mut config.minter_members, account);
    //      event::emit(RoleRevoked {
    //         role_name: string::utf8(b"MINTER_ROLE"),
    //         account: account,
    //         revoker: tx_context::sender(ctx),
    //     });
    // }

    // // Grant/Revoke DEFAULT_ADMIN_ROLE (special care for not removing all admins)
    // public entry fun grant_admin_role<USDC>(
    //     config: &mut CreditConfig<USDC>,
    //     account: address,
    //     ctx: &TxContext
    // ) {
    //     assert_admin(config, ctx); // Only an existing admin can grant admin role
    //     bag::add(&mut config.admin_members, account, true);
    //     event::emit(RoleGranted { role_name: string::utf8(b"DEFAULT_ADMIN_ROLE"), account, granter: tx_context::sender(ctx) });
    // }

    // public entry fun revoke_admin_role<USDC>(
    //     config: &mut CreditConfig<USDC>,
    //     account: address,
    //     ctx: &TxContext
    // ) {
    //     assert_admin(config, ctx);
    //     // Protect against accidentally removing all admins
    //     assert!(bag::length(&config.admin_members) > 1 || bag::borrow(&config.admin_members, account) != tx_context::sender(ctx), E_NO_ADMIN_EXISTS); // simplified check: ensure more than one or not revoking self if last
    //     // More robust: require(getRoleMemberCount(DEFAULT_ADMIN_ROLE) != 0 AFTER revoke)
    //     // Sui's bag::remove doesn't fail if item not present, so check count *after* or *before* if current member is the one being removed and is last.
    //     if (bag::length(&config.admin_members) == 1 && bag::contains(&config.admin_members, account) && account == tx_context::sender(ctx)) {
    //          assert!(false, E_NO_ADMIN_EXISTS); // Cannot remove self if last admin
    //     };
    //     bag::remove<address, bool>(&mut config.admin_members, account);
    //     // Ensure at least one admin remains. This check is tricky because remove doesn't error on non-existence.
    //     assert!(bag::length(&config.admin_members) > 0, E_NO_ADMIN_EXISTS);

    //     event::emit(RoleRevoked { role_name: string::utf8(b"DEFAULT_ADMIN_ROLE"), account, revoker: tx_context::sender(ctx) });
    // }
    // // ... Implement grant/revoke for BURNER_ROLE, TRANSFER_ALLOWED_ROLE, REDEEMER_ROLE, EMERGENCY_WITHDRAW_ROLE similarly ...
    //  public entry fun grant_transfer_allowed_role<USDC>(config: &mut CreditConfig<USDC>, account: address, ctx: &TxContext) {
    //     assert_admin(config, ctx); bag::add(&mut config.transfer_allowed_members, account, true);
    //     event::emit(RoleGranted{role_name: string::utf8(b"TRANSFER_ALLOWED_ROLE"), account, granter: tx_context::sender(ctx)});
    // }
    // public entry fun revoke_transfer_allowed_role<USDC>(config: &mut CreditConfig<USDC>, account: address, ctx: &TxContext) {
    //     assert_admin(config, ctx);
    //     bag::remove<address, bool>(&mut config.transfer_allowed_members, account);
    //     event::emit(RoleRevoked{role_name: string::utf8(b"TRANSFER_ALLOWED_ROLE"), account, revoker: tx_context::sender(ctx)});
    // }

    // --- Pausable Functions (callable by Admin) ---
    public entry fun pause(config: &mut CreditConfig<USDC>, ctx: &mut TxContext) {
        assert_has_role(config, tx_context::sender(ctx), ADMIN_ROLE);
        assert!(!config.is_paused, E_PAUSED); // Already paused
        config.is_paused = true;
        event::emit(Paused { pauser: tx_context::sender(ctx) });
    }

    public entry fun unpause(config: &mut CreditConfig<USDC>, ctx: &TxContext) {
        assert_has_role(config, tx_context::sender(ctx), ADMIN_ROLE);
        assert!(config.is_paused, E_NOT_PAUSED); // Already unpaused
        config.is_paused = false;
        event::emit(Unpaused { unpauser: tx_context::sender(ctx) });
    }

    // // --- _beforeTokenTransfer Logic Helpers ---
    // // Called during mint
    // fun assert_transfer_allowed_for_recipient<USDC>(config: &CreditConfig<USDC>, recipient: address) {
    //     assert!(has_role(&config.transfer_allowed_members, recipient), E_RECIPIENT_NOT_TRANSFER_ALLOWED);
    // }
    // // Called during burn
    // fun assert_transfer_allowed_for_sender<USDC>(config: &CreditConfig<USDC>, sender: address) {
    //     assert!(has_role(&config.transfer_allowed_members, sender), E_SENDER_NOT_TRANSFER_ALLOWED);
    // }
    // // Called during transfer
    // fun assert_transfer_allowed_for_parties<USDC>(config: &CreditConfig<USDC>, sender: address, recipient: address) {
    //     assert!(
    //         has_role(&config.transfer_allowed_members, sender) || has_role(&config.transfer_allowed_members, recipient),
    //         E_ONE_PARTY_MUST_BE_TRANSFER_ALLOWED
    //     );
    // }

    // --- Token Mint/Burn ---
    public entry fun mint(
        config: &mut CreditConfig<USDC>,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert_not_paused(config);
        assert_has_role(config, tx_context::sender(ctx), MINTER_ROLE);

        // Apply _beforeTokenTransfer logic for mint (to != address(0))
        // assert_transfer_allowed_for_recipient(config, recipient);

        let new_coins = coin::mint(&mut config.treasury_cap, amount, ctx);
        transfer::public_transfer(new_coins, recipient);
        event::emit(Minted { minter: tx_context::sender(ctx), recipient, amount });
    }

    // Burner burns their own tokens.
    // The Solidity `burn(address _from, ...)` is unusual. If it means burner can burn from anyone,
    // that requires a different model (e.g. contract holds all tokens in internal balances).
    // This implementation assumes burner burns coins they possess and pass to this function.
    public entry fun burn(
        config: &mut CreditConfig<USDC>,
        credit_coin: Coin<CREDIT_TOKEN>, // User provides the coin to burn
        ctx: &mut TxContext
    ) {
        assert_not_paused(config);
        let sender = tx_context::sender(ctx);
        assert_has_role(config, sender, BURNER_ROLE);

        // Apply _beforeTokenTransfer logic for burn (from != address(0))
        // assert_transfer_allowed_for_sender(config, sender); // Sender is the one whose coins are burned

        let coin_value = coin::value(&credit_coin);
        coin::burn(&mut config.treasury_cap, credit_coin);
        event::emit(Burned { burner: sender, amount: coin_value }); // Value before burn
    }

    // --- Oyster Market: Redeem CREDIT for USDC ---
    // TODO: remove usdc_amount parameter if it is always equal to credit_to_burn value.
    public fun redeem_and_burn<USDC>(
        config: &mut CreditConfig<USDC>,
        credit_to_burn: Coin<CREDIT_TOKEN>, // Redeemer provides their CREDIT coins
        usdc_recipient: address,     // Address to send USDC to
        usdc_amount: u64,            // Amount of USDC to redeem (and CREDIT to burn)
        ctx: &mut TxContext
    ) {
        assert_not_paused(config);
        let redeemer = tx_context::sender(ctx);
        // assert!(has_role(&config.redeemer_members, redeemer), E_NOT_REDEEMER);

        // Check if contract has enough USDC
        assert!(balance::value(&config.usdc_vault) >= usdc_amount, E_INSUFFICIENT_USDC_IN_CONTRACT);

        // Check _beforeTokenTransfer for burning CREDIT from redeemer
        // (assuming redeemer also needs TRANSFER_ALLOWED_ROLE implicitly or explicitly)
        // assert_transfer_allowed_for_sender(config, redeemer);

        // Burn the specified amount of CREDIT tokens from the provided coin
        // If credit_to_burn value is not exactly usdc_amount, handle it:
        // For simplicity, assume 1 CREDIT = 1 smallest unit of USDC, and decimals are aligned.
        // The Solidity version burns `_amount` CREDIT, which is also the USDC amount.
        assert!(coin::value(&credit_to_burn) == usdc_amount, E_INVALID_ROLE); // Reuse error or create specific one for amount mismatch
        coin::burn(&mut config.treasury_cap, credit_to_burn);

        // Transfer USDC from contract's vault to the recipient
        let usdc_payment = coin::take(&mut config.usdc_vault, usdc_amount, ctx);
        transfer::public_transfer(usdc_payment, usdc_recipient);

        // event::emit(RedeemedAndBurned { redeemer, usdc_recipient, amount: usdc_amount });
    }
    
    // Function for the contract to receive USDC
    public entry fun deposit_usdc(
        config: &mut CreditConfig<USDC>,
        usdc_coin: Coin<USDC>,
        ctx: &TxContext
    ) {
        // No specific role needed to deposit, unless desired.
        coin::put(&mut config.usdc_vault, usdc_coin);
    }


    // --- Emergency Withdraw (Admin capability) ---
    // This function allows admin to withdraw *any* token type held by the contract.
    // For USDC, it would use config.usdc_vault. For other tokens, they'd need to be stored similarly.
    // This example focuses on USDC from the vault.
    public entry fun emergency_withdraw_usdc(
        config: &mut CreditConfig<USDC>,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert_has_role(config, tx_context::sender(ctx), ADMIN_ROLE);
        // Check if recipient has EMERGENCY_WITHDRAW_ROLE (for receiving)
        assert_has_role(config, recipient, EMERGENCY_WITHDRAW_ROLE);
        assert!(balance::value(&config.usdc_vault) >= amount, E_INSUFFICIENT_USDC_IN_CONTRACT);

        let withdrawn_usdc = coin::take(&mut config.usdc_vault, amount, ctx);
        transfer::public_transfer(withdrawn_usdc, recipient);
        // event::emit(EmergencyWithdrawn { admin: tx_context::sender(ctx), token_type: "USDC", recipient, amount });
    }

    // // If a generic emergency withdraw for ANY token type held by the contract is needed,
    // // the contract would need to manage multiple `Balance<OTHER_TOKEN_TYPE>` fields,
    // // or a more complex generic storage solution.
    // // For the provided Solidity: `IERC20(_token).safeTransfer(_to, _amount);`
    // // This is simpler if only USDC is managed by this contract's Balance.

    // // --- Custom Transfer Function (to enforce _beforeTokenTransfer) ---
    // // Standard sui::transfer::transfer for Coin<CREDIT> will bypass these checks.
    // // Users would call this function to transfer CREDIT with the role checks.
    // public entry fun transfer_credit_tokens<USDC>(
    //     config: &CreditConfig<USDC>, // Read-only for checks
    //     credit_coin: Coin<CREDIT>,
    //     recipient: address,
    //     ctx: &TxContext
    // ) {
    //     assert_not_paused(config); // Assuming transfers are pausable
    //     let sender = tx_context::sender(ctx);
    //     // Apply _beforeTokenTransfer logic for a standard transfer
    //     assert_transfer_allowed_for_parties(config, sender, recipient);

    //     transfer::public_transfer(credit_coin, recipient);
    //     // event::emit(CreditTransferred { from: sender, to: recipient, amount: coin::value(&credit_coin) });
    // }

    // // --- Upgrade Authorization ---
    // // In Sui, actual upgrade is by the package publisher. This function can act as an on-chain approval step.
    // public entry fun authorize_upgrade<USDC>(config: &CreditConfig<USDC>, ctx: &TxContext) {
    //     assert_admin(config, ctx);
    //     // Logic to signal that an upgrade is authorized by admin.
    //     // Could emit an event or set a flag if needed by an off-chain upgrade process.
    //     // event::emit(UpgradeAuthorized { admin: tx_context::sender(ctx) });
    //     // For UUPS, Solidity's _authorizeUpgrade is an internal hook.
    //     // Here, it's an explicit function an admin calls.
    // }

    // // --- View Functions (Read-only) ---
    // public fun decimals<USDC>(config: &CreditConfig<USDC>): u8 {
    //     // The actual decimals are stored in CoinMetadata<CREDIT>
    //     // This function could fetch it if CoinMetadata ID is stored, or return constant.
    //     // For simplicity, returning the known constant.
    //     6
    // }

    public fun is_paused(config: &CreditConfig<USDC>): bool {
        config.is_paused
    }

    // public fun get_role_member_count<USDC>(config: &CreditConfig<USDC>, role_name_str: String): u64 {
    //     // Example: Map role_name_str to the correct bag and return its length.
    //     // This is illustrative; a more robust mapping or separate functions per role is better.
    //     if (role_name_str == string::utf8(b"DEFAULT_ADMIN_ROLE")) {
    //         bag::length(&config.admin_members)
    //     } else if (role_name_str == string::utf8(b"MINTER_ROLE")) {
    //         bag::length(&config.minter_members)
    //     } // ... and so on for other roles
    //     else { 0 }
    // }

    // public fun has_specific_role<USDC>(config: &CreditConfig<USDC>, account: address, role_name_str: String): bool {
    //     if (role_name_str == string::utf8(b"DEFAULT_ADMIN_ROLE")) {
    //         has_role(&config.admin_members, account)
    //     } else if (role_name_str == string::utf8(b"MINTER_ROLE")) {
    //         has_role(&config.minter_members, account)
    //     } // ... and so on
    //     else { false }
    // }

    // Add other view functions as needed, e.g., to get USDC balance, total supply of CREDIT (from TreasuryCap if accessible or CoinMetadata).
    public fun total_supply<USDC>(config: &CreditConfig<USDC>): u64 {
        coin::total_supply(&config.treasury_cap)
    }

    public fun contract_usdc_balance<USDC>(config: &CreditConfig<USDC>): u64 {
        balance::value(&config.usdc_vault)
    }

    #[test_only]
    public fun test_oyster_credits_init(ctx: &mut TxContext) {
        init(CREDIT_TOKEN {}, ctx);
    }
}