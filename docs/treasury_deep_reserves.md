# Treasury DEEP Reserves

## 1. Overview and Purpose

One of the core functions of the Deeptrade protocol is to simplify the trading experience on DeepBook. The underlying DeepBook protocol requires users to pay fees in its native `DEEP` token for actions like placing orders or swaps. This requirement can be a barrier to entry for users who do not hold `DEEP`.

The `Treasury`'s **DEEP Reserves** are designed to solve this problem. The protocol holds a reserve of `DEEP` tokens specifically to cover these fees on behalf of users, making trading on DeepBook accessible to everyone, regardless of whether they personally hold `DEEP` tokens.

> **Note:**
>
> As of DeepBook v3.1, users can pay fees in the input coin for orders and swaps. However, this option comes with a trade-off: DeepBook applies a `1.25x` fee penalty multiplier, resulting in 25% higher fees.
>
> The protocol's DEEP reserves system remains highly valuable as it allows users to access the lower, non-penalized DEEP-based fee rates without needing to hold DEEP tokens themselves.
>
> This structure incentivizes users to hold DEEP coins while ensuring trading accessibility for everyone.

The reserves are only utilized when a user's own `DEEP` balance (in their wallet or `BalanceManager`) is insufficient to cover the required DeepBook fees.

## 2. How It Works: The DEEP Reserve Coverage Fee

When a user executes an action that requires a `DEEP` fee they cannot cover, the protocol steps in:

1.  The protocol calculates the required amount of `DEEP` needed for the DeepBook fee.
2.  This amount is drawn from the `Treasury.deep_reserves` and used to pay the fee.
3.  In exchange, the protocol charges the user a **DEEP Reserve Coverage Fee**. This fee is paid in a liquid asset (SUI) and is calculated to be the fair market value of the `DEEP` that was used.

This mechanism ensures a seamless experience for the user while compensating the protocol for the `DEEP` it provided.

> **Note:**
>
> 1.  When the pool is whitelisted by DeepBook, the protocol doesn't provide any DEEP, since such pools don't have DEEP fees.
> 2.  If a user has enough DEEP in their wallet or balance manager, the protocol doesn't provide any DEEP.

## 3. Economic Sustainability

The DEEP reserves are designed to be economically self-sustaining, posing minimal risk to the protocol. The sustainability is built on a simple principle: a fair value exchange.

- **SUI-Denominated Fees:** By collecting the `DEEP Reserve Coverage Fee` in SUI, the protocol receives a liquid asset.
- **1:1 Value Exchange:** The fee is not arbitrary. It is calculated to match the exact market value of the `DEEP` provided at the time of the transaction.

This creates a closed economic loop. The SUI collected can be used to purchase `DEEP` from the open market, thereby replenishing the reserves. This ensures the protocol can continue to provide this service indefinitely without depleting its reserve assets.

## 4. Protecting the Reserves

The integrity of the economic model hinges on the ability to get a fair, manipulation-resistant market price for `DEEP/SUI`. Relying solely on the on-chain DeepBook pool price for this calculation would introduce a severe vulnerability that could allow an attacker to drain the reserves.

To prevent this, the protocol implements a **dual-price security mechanism**. This system leverages both on-chain pool data and external oracle feeds to establish a secure price for calculating the `DEEP Reserve Coverage Fee`.

This approach is critical for protecting the protocol's assets. The specific attack vectors it prevents are detailed in the [Oracle Pricing Security](./oracle-pricing-security.md), and the technical implementation of the price calculation is explained in the [Oracle Price Calculation](./oracle-price-calculation.md).
