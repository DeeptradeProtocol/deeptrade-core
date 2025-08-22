<p align="center">
  <img src="./assets/sui-deeptrade-dynamic-logo.svg" alt="Sui Deeptrade Logo" style="border: none; background: transparent;">
</p>

# Deeptrade Core

## Overview

TBD

## System Design

For detailed technical specifications and implementation details, please refer to:

- [Treasury DEEP Reserves](docs/treasury_deep_reserves.md)
- [Fee Design](docs/fee-design.md)
- [Loyalty Program](docs/loyalty.md)
- [Oracle Price Calculation](docs/oracle-price-calculation.md)
- [Oracle Pricing Security](docs/oracle-pricing-security.md)
- [Unsettled Fees](docs/unsettled-fees.md)
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
```

## Upgrade Cap:

```

```

## Admin Cap:

```

```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.

This tool uses several dependencies from [Mysten Labs](https://github.com/MystenLabs/sui), which are licensed under Apache-2.0.
