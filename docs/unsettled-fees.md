# Unsettled Fees System

## Overview

The Deeptrade protocol charges fees for order execution, not for order placement. This is achieved through a dynamic system that holds potential fees for live orders and settles them based on the final outcome. This ensures that users only pay for the portion of their orders that actually execute.

## The Two Unsettled Fee Pools

All protocol fee operations are managed through the `FeesManager` object, which contains two distinct fee pools stored in Sui `Bag` objects:

1.  **`user_unsettled_fees`**: This pool holds `UserUnsettledFee` objects, each created for the **maker portion** of a limit order (the part that rests on the book). An object persists in this pool even after its order is filled, until it is processed by a settlement function.

2.  **`protocol_unsettled_fees`**: This pool aggregates all fees that have been earned by the protocol but not yet transferred to the treasury. This includes taker fees, the protocol's share of maker fees from partially filled orders, and any other protocol-bound fees. It holds `Balance` objects, one for each coin type.

## The Fee Lifecycle

A fee moves through several stages from its creation to its final collection in the treasury.

### 1. Fee Creation

When a user places a limit order, any portion that rests on the book is its "maker portion". The potential maker fee is calculated for this portion and stored as a `UserUnsettledFee` object in the `user_unsettled_fees` bag.

### 2. Settlement

Settlement happens in one of two ways, depending on how the order is finalized.

#### Path A: Order Cancellation by User

If a user cancels their own order, the associated `UserUnsettledFee` is settled immediately and completely. The logic is as follows:

- The fee for the **unfilled portion** of the order is returned directly to the user as a `Coin`.
- The fee for the **filled portion** is moved into the `protocol_unsettled_fees` bag for later collection.
- The original `UserUnsettledFee` object is destroyed, granting the user an immediate gas storage rebate.

#### Path B: Order Completion or Protocol-Side Collection

When an order is completed (e.g., fully filled) or cancelled externally, the fees can be settled permissionlessly by anyone through a batch process.

1.  **Settle Filled Order Fees**: Anyone can call `settle_filled_order_fee_and_record` for any finalized order. This function drains the entire fee from the `UserUnsettledFee` object and sends it directly to the protocol treasury. It intentionally leaves the now-empty `UserUnsettledFee` object in the bag.

2.  **Settle Protocol Fees**: Anyone can call `settle_protocol_fee_and_record`. This function drains the aggregated balances from the `protocol_unsettled_fees` bag and sends them to the treasury. It also leaves empty `Balance` objects in the bag.

### 3. Storage Rebate Claims

The permissionless settlement functions (Path B) intentionally leave empty objects in the bags. This is a crucial design choice that separates fee collection from storage rebate claims.

- The original owner of the `FeesManager` (or a protocol admin) must call one of the `claim_*_storage_rebate` functions to destroy these empty objects and reclaim the initial storage deposit.
- This two-step process separates permissionless fee collection from permissioned rebate claims. It allows anyone to help settle protocol fees, while ensuring that only the rightful owner of the `FeesManager` can claim the storage rebate for the object they initially paid to create.

## Order Type Support

The system is designed to handle fees correctly for various order types supported by DeepBook:

- **Immediate-Or-Cancel (IOC)**: An IOC order executes as much as it can immediately (the taker portion) and cancels the rest. It does not rest on the book, so it **does not generate** a `UserUnsettledFee`.

- **Fill-Or-Kill (FOK)**: An FOK order must be filled entirely and immediately (as a taker). If it cannot be fully filled, the entire order is rejected. Like IOC, it **does not generate** a `UserUnsettledFee`.

- **Post-Only**: This order type is designed to only be a maker. If any part of the order would execute immediately as a taker, the entire order is rejected. Therefore, it **always generates** a `UserUnsettledFee` for the full order amount.

- **Good-Til-Cancelled (GTC)**: This is the most complex case. A GTC order can be partially taker (if it crosses the spread on placement) and partially maker (the remainder that rests on the book). A `UserUnsettledFee` is created **only for the maker portion**.

### Examples

**Market Order (IOC)**:
If 75% of the order executes, the user pays taker fees for that executed portion. The remaining 25% is automatically cancelled. No `UserUnsettledFee` is created.

**FOK Order**:
The order is either 100% filled (paying only taker fees) or completely rejected. No `UserUnsettledFee` is created in either case.

**Post-Only Order**:
The order either remains entirely in the order book or is rejected. If placed successfully, a `UserUnsettledFee` is created for 100% of the order amount.

**GTC Order**:
If 10% of the order executes immediately, the user pays taker fees for that 10% portion. A `UserUnsettledFee` is created for the remaining 90% maker portion that rests on the order book.

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

- **Risk**: If a user cancels an order directly on DeepBook without using the `deeptrade-core` settlement functions, they forfeit any potential refund from their unsettled maker fee.
- **Reason**: The `settle_user_fees` function, which calculates the user's refund, must be called _before_ an order is cancelled. If an order is cancelled externally, this function can no longer be used. The only remaining way to process the fee is through the permissionless `settle_filled_order_fee_and_record` function, which sends the entire fee amount to the protocol.
