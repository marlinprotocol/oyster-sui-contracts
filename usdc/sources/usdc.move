/*
/// Module: oyster_usdc
module oyster_usdc::oyster_usdc;
*/

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

module usdc::usdc {
  use sui::coin;

  public struct USDC has drop {}

  fun init(witness: USDC, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
      witness,
      6,                             // USDC uses 6 decimals
      b"USDC",                       // Symbol
      b"USD Coin",                   // Name
      b"A stablecoin pegged to USD",// Description
      option::none(),               // No icon URL
      ctx
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, tx_context::sender(ctx));
  }

  public entry fun mint(
    cap: &mut coin::TreasuryCap<USDC>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext
  ) {
    coin::mint_and_transfer(cap, amount, recipient, ctx);
  }
}
