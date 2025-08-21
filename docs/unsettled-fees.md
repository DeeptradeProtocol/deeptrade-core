# Unsettled Fees System

## Overview

The Deeptrade protocol charges fees for order execution, not for order placement. This is achieved through a dynamic system that holds unsettled fees for live orders and settles them based on the final outcome. This ensures that users only pay for the portion of their orders that actually execute.

## Design Motivation: The FeeManager

To handle fee management at scale, the protocol introduces a dedicated `FeeManager` object for each user. This design is a direct solution to the challenge of **shared object congestion** on the Sui network, a scenario where too many transactions attempting to modify the same object can lead to performance bottlenecks and transaction failures.

A more naive approach would be to store all unsettled fee data within the single, global `Treasury` object. However, this would mean that every trade from every user would need to write to the same object, creating a significant point of contention. As the official Sui documentation advises, developers should "avoid using a single shared object if possible" to prevent this exact problem ([Object-Based Local Fee Markets](https://docs.sui.io/guides/developer/advanced/local-fee-markets)).

By giving each user their own `FeeManager`, the system elegantly sidesteps this issue. Instead of a single "hot" object, fee operations are distributed and parallelized across many user-specific objects. This architecture is fundamental to ensuring the protocol remains fast, reliable, and scalable, even under heavy trading volume, as detailed in Sui's approach to [congestion control](https://blog.sui.io/shared-object-congestion-control/).

## The `FeeManager` Structure

All protocol fee operations are managed through the `FeeManager` object. This object has two primary fields for managing fees, both of which are implemented as Sui `Bag` objects:

1.  **`user_unsettled_fees`**: This field holds `UserUnsettledFee` structs, each created for the **maker portion** of a limit order (the part that rests in the order book). A struct persists in this bag even after its order is filled, until it is processed by a settlement function.

2.  **`protocol_unsettled_fees`**: This field aggregates all fees that have been earned by the protocol but not yet transferred to the treasury. This includes taker fees, the protocol's share of maker fees from partially filled orders. It holds `Balance` values, one for each coin type.

## The Fee Lifecycle

A fee moves through several stages from its creation to its final settlement in the treasury.

### 1. Fee Creation

When a user places a limit order, any portion that rests in the order book is its "maker portion". The maker fee is calculated for this portion and stored as a `UserUnsettledFee` struct in the `user_unsettled_fees` bag.

### 2. Settlement

Settlement happens in one of two ways, depending on how the order is finalized.

#### Path A: Order Cancellation by User

If a user cancels their own order, the associated `UserUnsettledFee` is settled immediately and completely. The logic is as follows:

- The fee for the **unfilled portion** of the order is returned directly to the user as a `Coin`.
- The fee for the **filled portion** is moved into the `protocol_unsettled_fees` bag for later settlement.
- The original `UserUnsettledFee` struct is destroyed, granting the user an immediate gas storage rebate.

#### Path B: Order Completion or Protocol-Side Settlement

When an order is completed (e.g., fully filled) or cancelled externally, the fees can be settled permissionlessly by anyone through a batch process.

1.  **Settle Filled Order Fees**: Anyone can call `settle_filled_order_fee_and_record` for any finalized order. This function withdraws the entire fee from the `UserUnsettledFee` struct and sends it directly to the protocol treasury. It intentionally leaves the now-empty `UserUnsettledFee` struct in the bag.

2.  **Settle Protocol Fees**: Anyone can call `settle_protocol_fee_and_record`. This function withdraws the aggregated balances from the `protocol_unsettled_fees` bag and sends them to the treasury. It also leaves empty `Balance` values in the bag.

### 3. Storage Rebate Claims

The permissionless settlement functions (Path B) intentionally leave empty structs and values in the bags. This is a crucial design choice that separates fee settlement from storage rebate claims.

- The user who owns the `FeeManager` has the primary right to reclaim their initial storage deposit by calling one of the `claim_*_storage_rebate` functions. This action destroys the now-empty structs, returning the storage fee to the user.

- For the long-term health and economic sustainability of the protocol, a protocol admin may also perform this cleanup. At a large scale, with potentially millions of users, the gas cost of settling countless small protocol fees can exceed the value of the fees themselves. Reclaiming the storage fees from abandoned structs helps subsidize these essential maintenance operations. This ensures that the fee settlement system remains efficient and economically viable for the protocol, which benefits all users by keeping the platform running smoothly.

## Order Type Support

The system is designed to handle fees correctly for various order types supported by DeepBook:

- **Immediate-Or-Cancel (IOC)**: An IOC order executes as much as it can immediately (the taker portion) and cancels the rest. It does not rest in the book, so it **does not generate** a `UserUnsettledFee`.

- **Fill-Or-Kill (FOK)**: An FOK order must be filled entirely and immediately (as a taker). If it cannot be fully filled, the entire order is rejected. Like IOC, it **does not generate** a `UserUnsettledFee`.

- **Post-Only**: This order type is designed to only be a maker. If any part of the order would execute immediately as a taker, the entire order is rejected. Therefore, it **always generates** a `UserUnsettledFee` for the full order amount.

- **Good-Til-Cancelled (GTC)**: This is the most complex case. A GTC order can be fully taker and fully maker, partially taker (if it crosses the spread on placement) and partially maker (the remainder that rests in the book). A `UserUnsettledFee` is created **only for the maker portion**.

### Examples

**Market Order (IOC)**:
If 75% of the order executes, the user pays taker fees for that executed portion right away. The remaining 25% is automatically cancelled. No `UserUnsettledFee` is created.

**FOK Order**:
The order is either 100% filled (paying only taker fees) or completely rejected. No `UserUnsettledFee` is created in either case.

**Post-Only Order**:
The order either remains entirely in the order book or is rejected. If placed successfully, a `UserUnsettledFee` is created for 100% of the order amount.

**GTC Order**:
If 10% of the order executes immediately, the user pays taker fees for that 10% portion. A `UserUnsettledFee` is created for the remaining 90% maker portion that rests in the order book.

## Swap Fee Handling

Unlike limit orders which use the `FeeManager` system for unsettled fees, swap operations directly transfer protocol fees to the treasury. This design choice intentionally accepts the risk of `Treasury` shared object congestion for the following reasons:

1. **Gas Optimization**: Using the `FeeManager` system for swaps would require user to create a protocol fee dynamic field inside of the fee manager for each coin the user hasn't swapped before. In cases where users have multiple hops in a single swap, creating such dynamic fields for each output coin becomes significantly more gas expensive. Despite the fact that this storage gas fee is reclaimable and is created only once per coin, using the `Treasury` object directly avoids this cost, making the swap UX more gas-efficient on a daily basis.

2. **User Priority Fee Control**: Users can set priority fees at any time to ensure their swap transactions are processed even during `Treasury` object congestion.

3. **Economic Incentive for Limit Orders**: During high-peak trading volumes when `Treasury` object congestion may occur, slippage on swaps typically reaches significant values. In these conditions, users are more economically driven to place limit orders at their desired prices rather than executing swaps with high slippage, which would result in losing substantial amounts of their desired tokens.

## Protocol Fee Discounts

The system offers protocol fee discounts when using the DEEP fee type, designed to incentivize DEEP holders:

- **DEEP Fee Coverage Discounts**: The more DeepBook fees the user covers with their own DEEP tokens, the higher their discount
- **Maximum discount**: Achieved when the user fully covers the DeepBook fees themselves
- **Whitelisted pools**: Automatically receive the maximum protocol fee discount rate for each order
- **Configuration**: Maximum discount rates are specified for each pool in the `TradingFeeConfig`, alongside the standard fee rates

Additionally, the system includes a **Loyalty Program** that provides additional protocol fee discounts based on user loyalty levels. For detailed information about the loyalty program, see the [loyalty.md](./loyalty.md) documentation.

## Design Limitations

### 1. Order Expiration Time

- **Limitation**: Only orders without expiration time are supported
- **Reason**: If an order expires, there's no technical way to return unsettled fees to the user, because expired orders no longer exist in the order book and become inaccessible

### 2. Self-Matching Options

- **Limitation**: Self-matching types like "cancel maker" or "cancel taker" are not supported
- **Reason**: These options can implicitly cancel the user's own orders, blocking fee settlement since cancelled orders no longer exist in the order book and become inaccessible

### 3. Order Modifications

- **Current status**: Order modifications are not allowed
- **Future improvement**: Will require a custom function (similar to cancellation) to properly settle fees during modifications

### 4. External Order Cancellation

- **Limitation**: To receive the user‑owed maker fee for the unfilled portion (returned as a `Coin<FeeCoinType>`), an order should be cancelled using a protocol function that settles fees in the same step (for example, `cancel_order_and_settle_fees`). If an order is cancelled on an external platform that doesn’t run this function, the user‑owed amount cannot be settled afterwards.

- **Reason**: Settlement requires the order’s final fill state. After an external cancellation, the order is removed from the book and this state is no longer accessible to the protocol, so the unfilled portion cannot be computed or returned.
