<p align="center">
  <img src="./assets/sui-deeptrade-dynamic-logo.svg" alt="Sui Deeptrade Logo" style="border: none; background: transparent;">
</p>

# Deeptrade Core

## Overview

This package is a **comprehensive on-chain trading protocol suite** built to enhance and secure liquidity operations on the Sui network's DeepBook order book.

A core design principle is extending DeepBook's capabilities without sacrificing composability. This approach ensures users can freely manage orders created via the protocol using native DeepBook operations, preventing platform lock-in and granting full autonomy over their trading activity.

Crucially, this design also preserves the security of the underlying DeepBook protocol. The protocol does not take custody of user orders or assets; it only manages the fees generated through its usage.

This significantly minimizes risk for end users, even if the protocol were to cease operations, users would retain uninterrupted control and could continue managing their orders and assets directly on DeepBook.

Deeptrade Core introduces a self-sustaining economic model centered around a core **Treasury** that manages protocol-owned liquidity for `DEEP` tokens. This allows for a more accessible trading experience by abstracting the native fee token requirements of the underlying order book.

The protocol's key innovation is its robust **Fee and Liquidity Management Engine**, which includes:

- **Dynamic Fee Generation**: A configurable fee engine that generates protocol revenue from trading activity. It allows for distinct taker/maker rates, which can be set independently based on the fee type used (DEEP or Input Coin). This flexibility is crucial for incentivizing the use of the `DEEP` token, thereby strengthening the protocol's economic model.
- **Unsettled Fees System**: A fair and scalable mechanism that ensures fees are only charged on executed trade volumes, utilizing per-user `FeeManager` objects to prevent **shared object contention** and ensure the protocol remains highly scalable.
- **Oracle-Secured Pricing**: A dual-validation system that leverages both on-chain pool data and external Pyth oracle feeds to protect the protocol's reserves from atomic price manipulation attacks.
- **Gas Efficiency**: The protocol is designed with gas efficiency as a key consideration. By optimizing on-chain storage and computation, transaction costs are minimized for users, ensuring a more cost-effective trading experience.
- **DEEP Token Utility**: The protocol creates strong utility for the `DEEP` token. For accessibility, the Treasury's DEEP Reserves cover DeepBook fees on behalf of users, who then repay the protocol with a market-rate coverage fee in SUI. To incentivize holding `DEEP`, users who cover DeepBook fees with their own `DEEP` tokens pay no coverage fee and also receive substantial discounts on protocol fees.
- **User Incentives**: An integrated Loyalty Program that rewards high-volume traders with fee discounts, encouraging sustained platform activity.

Governance and security are paramount, enforced through an **on-chain Multisig Guarantee** that hardcodes multi-signature verification into all sensitive administrative functions.

High-risk operations, such as withdrawals from the protocol's treasury and fee updates, are further protected by a mandatory, event-logged **Timelock System**. This system is designed with two key goals: to provide users with full transparency and a response window for changes that could affect them, such as fee increases, and to adding security layer for the protocol by safeguarding treasury reserves against unauthorized withdrawals.

The protocol is designed for long-term maintainability with a built-in **Versioning System**, allowing for secure and seamless upgrades.

To further enhance transparency around upgrades, the protocol will adopt a **Custom Upgrade Policy** for its `UpgradeCap`. This initiative directly addresses the critical need for observable package upgrades — a challenge recognized within the broader Sui ecosystem (see [Sui Improvement Proposal #57](https://github.com/sui-foundation/sips/pull/57/files)). The custom policy, currently in draft (see [PR #75](https://github.com/DeeptradeProtocol/deeptrade-core/pull/75)), will provide essential on-chain visibility for any upgrade event. This lays the groundwork for a future upgrade timelock, ensuring the community has a crucial window to review and react to changes, safeguarding against unauthorized modifications.

## System Design

For detailed technical specifications and implementation details, please refer to:

- [Treasury DEEP Reserves](docs/treasury_deep_reserves.md)
- [Fee Design](docs/fee-design.md)
- [Loyalty Program](docs/loyalty.md)
- [Oracle Price Calculation](docs/oracle-price-calculation.md)
- [Oracle Pricing Security](docs/oracle-pricing-security.md)
- [Unsettled Fees](docs/unsettled-fees.md)
- [Gas Consumption](docs/gas-consumption.md)
- [Versioning](docs/versioning.md)
- [Multisig](docs/multisig.md)
- [Admin Capabilities](docs/admin.md)
- [Development Notes](docs/dev-notes.md)

## Fee overview

### Order Fees

DeepBook protocol requires paying fees for order placement in either DEEP or the order's input asset (DEEP-based fee or Input Coin fee types), with fees calculated based on order price and size. Deeptrade protocol extends this flexibility by allowing users to pay these fees using various sources: their wallet, their `BalanceManager`, or even the protocol's treasury DEEP reserves if the user's DEEP balance is insufficient.

**Protocol Fees**: In addition to DeepBook's fees, the Deeptrade charges its own protocol fees. These fees can be configured with different rates for taker and maker orders, and can be set globally or on a per-pool basis.
For detailed information about dynamic protocol fee calculation, and the unsettled fees mechanism, see the [Fee Design](docs/fee-design.md) and [Unsettled Fees](docs/unsettled-fees.md) documentation.

**DEEP Reserve Coverage Fee**: This fee is charged only when a user borrows `DEEP` from the protocol's reserves to cover DeepBook fees. It is paid in SUI and is equivalent to the market value of the `DEEP` provided. More information is available in the [Treasury DEEP Reserves](docs/treasury_deep_reserves.md).

#### Protocol Fee Discounts

When using DEEP fee type, users can receive discounts on protocol fees based on how much DeepBook fees they cover with their own DEEP tokens. The more DEEP the user provides, the higher their discount on protocol fees.
Whitelisted pools receive the maximum protocol fee discount rate for each order. The discount rates are per-pool based and set in `TradingFeeConfig`, with a default rate of 25% used if not specified.

Additionally, the system includes a **Loyalty Program** that provides additional protocol fee discounts based on user loyalty levels. For detailed information about the loyalty program, see the [Loyalty Program](docs/loyalty.md).

## Swap Fees

Similar to order fees, the DeepBook protocol requires paying fees for swaps in either `DEEP` or the swap's input coin (DEEP-based or Input Coin fee types), calculated based on the swap size.

Deeptrade charges its own fees using the `taker_fee` parameter specified in `TradingFeeConfig`. For swaps, the protocol currently only supports the Input Coin fee type.

The protocol fee is charged in the output coin of the swap.
Discounts from the [Loyalty Program](docs/loyalty.md) also apply to swap fees.

## Deeptrade Core Package Ids:

```
0x1271ca74fee31ee2ffb4d6373eafb9ada44cdef0700ca34ec650b21de60cc80b
0xd7ca30ad715278a28f01c572ac7be3168e9800321f1b3f96eb9d13dfc856419c
0xc6fa96e203d7858e1925563bdc2c75d1c2ff57af90cad46a7ad3364573e20fb0
0x90cffe4f0670e0c4d3413c124c364301fc0e73c709ada13ba86f2398c44a135a
0x55febc53366b6ced945b1adf5ebd3f8628d940664782e51937cc93513ad83339
0x4af08dd22015fdabeae5f2b883dca9fca4f7de88434dae7cea712d247658b68d
0x208d664e59ad391212a11ad8658d0e9d7510c6cd1785bd0d477d73505d5c89b1
0xc49f720f4e8427cbd3955846ca9231441dab8ccda6c3da6e9d44ed6f9dcf865c
0x2356885eae212599c0c7a42d648cc2100dedfa4698f8fc58fc6b9f67806f2bfc
0x03aafc54af513d592bcb91136d61b94ea40b0f9b50477f24a3a9a38fca625174
0x232b6dccf004919ce5deb1a7ee3d0e9f1c71170c9402ec1918aa212754baadb3
0xc10d536b6580d809711b9bb8eee3945d5e96f92a346c84d74ff7a0697e664695
```

## Upgrade Cap:

```
0x331c41b3587619223c8ccf44b2aa9ad683fae7b536d6b5ed96fc94fe9a8d4278
```

## Admin Cap:

```
0xe92f79ac54409c9eecfd77ce1089edd9b424b87c6cba8aa99c8fedb64d0e0b8b
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.

This tool uses several dependencies from [Mysten Labs](https://github.com/MystenLabs/sui), which are licensed under Apache-2.0.
