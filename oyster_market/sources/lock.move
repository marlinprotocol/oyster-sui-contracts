module oyster_market::lock {
    // use std::vector;
    // use std::string;
    use sui::bcs;
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::hash; // keccak256
    // use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    // use sui::transfer;
    // use sui::tx_context::{Self as tx, TxContext};

    /// ------------------------------------------------------------------------
    /// Types
    /// ------------------------------------------------------------------------

    /// Mirrors the Solidity `Lock` struct
    public struct Lock has drop, store, copy {
        unlock_time: u64, // milliseconds since Unix epoch
        i_value: u256,
    }

    /// Shared state that holds all locks and selector wait times.
    public struct LockData has key {
        id: UID,
        /// lock_id (keccak256(selector || key)) -> Lock
        locks: Table<vector<u8>, Lock>,
        /// selector -> wait time in milliseconds
        lock_wait_times: Table<vector<u8>, u64>,
    }

    /// One-time init witness pattern. Create this private type with your package
    public struct LockInit has drop {}

    /// ------------------------------------------------------------------------
    /// Events (parity with Solidity events)
    /// ------------------------------------------------------------------------
    public struct LockWaitTimeUpdated has drop, copy, store {
        selector: vector<u8>,
        prev_lock_time: u64,
        updated_lock_time: u64
    }
    public struct LockCreated has drop, copy, store {
        selector: vector<u8>,
        key: vector<u8>,
        i_value: u256,
        unlock_time: u64
    }
    public struct LockDeleted has drop, copy, store {
        selector: vector<u8>,
        key: vector<u8>,
        i_value: u256
    }

    /// ------------------------------------------------------------------------
    /// Error codes (abort codes)
    /// ------------------------------------------------------------------------
    const E_LOCK_LENGTH_MISMATCH: u64 = 0;
    const E_LOCK_SHOULD_BE_NONE: u64 = 1;
    const E_LOCK_SHOULD_BE_UNLOCKED: u64 = 2;

    /// Lock status enum like Solidity. 0=None, 1=Unlocked, 2=Locked
    const STATUS_NONE: u8 = 0;
    const STATUS_UNLOCKED: u8 = 1;
    const STATUS_LOCKED: u8 = 2;

    /// ------------------------------------------------------------------------
    /// Init
    /// ------------------------------------------------------------------------
    fun init(ctx: &mut TxContext) {
        let lock_data = LockData {
            id: object::new(ctx),
            locks: table::new<vector<u8>, Lock>(ctx),
            lock_wait_times: table::new<vector<u8>, u64>(ctx)
        };
        transfer::share_object(lock_data);
    }

    /// ------------------------------------------------------------------------
    /// Pure helpers
    /// ------------------------------------------------------------------------
    /// lock_id = keccak256( bcs(selector) || bcs(key) )
    public fun lock_id(
        selector: &vector<u8>,
        key: &vector<u8>
    ): vector<u8> {
        let mut bytes = bcs::to_bytes(selector);
        vector::append(&mut bytes, bcs::to_bytes(key));
        hash::keccak256(&bytes)
    }

    /// Returns current timestamp in ms from the system Clock.
    fun now_ms(clock: &Clock): u64 {
        clock::timestamp_ms(clock)
    }

    /// ------------------------------------------------------------------------
    /// Read ("view")
    /// ------------------------------------------------------------------------
    public fun lock_wait_time_ms(
        lock_data: &LockData,
        selector: vector<u8>
    ): u64 {
        if (table::contains(&lock_data.lock_wait_times, selector)) {
            *table::borrow(&lock_data.lock_wait_times, selector)
        } else { 0 }
    }

    public fun lock_status(
        lock_data: &LockData,
        selector: &vector<u8>,
        key: &vector<u8>,
        clock: &Clock
    ): u8 {
        let id = lock_id(selector, key);
        if (!table::contains(&lock_data.locks, id)) { return STATUS_NONE };
        let unlock_time = table::borrow(&lock_data.locks, id).unlock_time;
        let now = now_ms(clock);
        if (unlock_time <= now) STATUS_UNLOCKED else STATUS_LOCKED
    }

    public fun lock_status_none(): u8 { STATUS_NONE }

    /// ------------------------------------------------------------------------
    /// Mutations
    /// ------------------------------------------------------------------------
    public(package) fun lock(
        lock_data: &mut LockData,
        selector: vector<u8>,
        key: vector<u8>,
        i_value: u256,
        clock: &Clock
    ): u64 {
        let status = lock_status(lock_data, &selector, &key, clock);
        assert!(status == STATUS_NONE, E_LOCK_SHOULD_BE_NONE);

        let duration = lock_wait_time_ms(lock_data, selector);
        let id = lock_id(&selector, &key);
        let unlock_time = now_ms(clock) + duration;
        let l = Lock { unlock_time: unlock_time, i_value }; 
        table::add(&mut lock_data.locks, id, l);
        event::emit(LockCreated { selector, key, i_value, unlock_time: unlock_time });
        unlock_time
    }

    public(package) fun revert_lock(
        lock_data: &mut LockData,
        selector: vector<u8>,
        key: vector<u8>
    ): u256 {
        let id = lock_id(&selector, &key);
        if(table::contains(&lock_data.locks, id)) {
            let l = table::remove(&mut lock_data.locks, id);
            let i_value = l.i_value;
            event::emit(LockDeleted { selector, key, i_value });
            i_value
        } else { 0 }
    }

    public(package) fun unlock(
        lock_data: &mut LockData,
        selector: vector<u8>,
        key: vector<u8>,
        clock: &Clock,
    ): u256 {
        let status = lock_status(lock_data, &selector, &key, clock);
        assert!(status == STATUS_UNLOCKED, E_LOCK_SHOULD_BE_UNLOCKED);
        revert_lock(lock_data, selector, key)
    }

    public(package) fun clone_lock(
        lock_data: &mut LockData,
        selector: vector<u8>,
        from_key: vector<u8>,
        to_key: vector<u8>,
        _ctx: &mut TxContext
    ) {
        let from_id = lock_id(&selector, &from_key);
        let to_id   = lock_id(&selector, &to_key);
        let src = *table::borrow(&lock_data.locks, from_id);
        if (table::contains(&lock_data.locks, to_id)) {
            table::remove(&mut lock_data.locks, to_id);
        };
        let l = Lock { unlock_time: src.unlock_time, i_value: src.i_value };
        table::add(&mut lock_data.locks, to_id, l);
        event::emit(LockCreated { selector, key: to_key, i_value: src.i_value, unlock_time: src.unlock_time });
    }

    /// ------------------------------------------------------------------------
    /// Admin updates
    /// ------------------------------------------------------------------------
    fun update_lock_wait_time(
        lock_data: &mut LockData,
        selector: vector<u8>,
        new_wait_ms: u64,
        _ctx: &mut TxContext
    ) {
        let prev = if (table::contains(&lock_data.lock_wait_times, selector)) {
            *table::borrow(&lock_data.lock_wait_times, selector)
        } else { 0 };

        event::emit(LockWaitTimeUpdated {
            selector,
            prev_lock_time: prev,
            updated_lock_time: new_wait_ms
        });
        if (table::contains(&lock_data.lock_wait_times, selector)) {
            *table::borrow_mut(&mut lock_data.lock_wait_times, selector) = new_wait_ms;
        } else {
            table::add(&mut lock_data.lock_wait_times, selector, new_wait_ms);
        }
    }

    public(package) fun update_lock_wait_times(
        lock_data: &mut LockData,
        selectors: vector<vector<u8>>,
        new_waits_ms: vector<u64>,
        ctx: &mut TxContext
    ) {
        let len = vector::length(&selectors);
        assert!(len == vector::length(&new_waits_ms), E_LOCK_LENGTH_MISMATCH);
        let mut i = 0;
        while (i < len) {
            let selector = *vector::borrow(&selectors, i);
            let wait_time = *vector::borrow(&new_waits_ms, i);
            update_lock_wait_time(lock_data, selector, wait_time, ctx);
            i = i + 1;
        }
    }

    // --- Tests ---
    #[test_only]
    public fun test_lock_init(ctx: &mut TxContext) {
        init(ctx);
    }

}
