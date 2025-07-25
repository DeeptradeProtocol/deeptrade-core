# Admin Capabilities

The `deeptrade-core` package is managed by an administrative entity that holds the `AdminCap`. To balance security, observability, and operational flexibility, we employ a two-tiered system for authorizing administrative actions. All of these actions are additionally protected by a onchain multisig enforcement layer, as detailed in our [Multisig](./multisig.md) document.

## 1. Direct AdminCap Operations

For operations that are considered lower-risk or require immediate execution for operational flexibility and emergency response, authorization is granted directly via the `AdminCap`.

### Operations

- **Version Management** (`wrapper.move`):
  - `enable_version`: Enables a new package version.
  - `disable_version`: Permanently disables an old package version.
- **Loyalty Program Management** (`loyalty.move`):
  - `add_loyalty_level` / `remove_loyalty_level`: Manages the available loyalty tiers.
  - `grant_user_level` / `revoke_user_level`: Assigns or removes loyalty tiers for specific users.

### Design Motivation

- **Emergency Response:** Versioning functions do not use a timelock to allow for rapid response in case of a critical bug or an issue with a dependency like the DeepBook protocol. This agility is crucial to protect the protocol and its users, as detailed in our [Versioning Strategy](./versioning.md).
- **Operational Flexibility:** The loyalty program is designed to be managed dynamically. We consider these operations to be low-risk, as the primary impact is on user fee discounts rather than a direct risk to locked funds. This flexibility allows us to manage the program efficiently without the delay of a timelock.

---

## 2. Timelocked Operations (AdminTicket)

For more sensitive operations, especially those involving the movement of funds, we introduce a mandatory timelock mechanism through the use of an `AdminTicket`.

An administrator must first create a ticket for a specific action by calling `ticket::create_ticket`. This action is publicly logged as a Sui event. The ticket can only be "consumed" to execute the intended action after a `TICKET_DELAY_DURATION` (2 days) has passed and before it expires after `TICKET_ACTIVE_DURATION` (3 days).

### Operations

- **Fund Withdrawal** (`wrapper.move`):
  - `withdraw_deep_reserves`: Withdraws DEEP tokens from the protocol's main reserves.
  - `withdraw_protocol_fee`: Withdraws collected protocol fees for a specific coin type.
  - `withdraw_deep_reserves_coverage_fee`: Withdraws collected coverage fees for a specific coin type.
- **Fee Configuration** (`fee.move`, `pool.move`):
  - `update_pool_creation_protocol_fee`: Changes the protocol fee required to create a new pool.
  - `update_default_fees`: Changes the global, default trading fee configuration.
  - `update_pool_specific_fees`: Sets or updates a custom trading fee configuration for a specific pool.

### Design Motivation

1.  **Observability and Trust:** The timelock system provides transparency. By emitting a `TicketCreated` event with a specific `ticket_type`, we signal our intent for sensitive actions to the community in advance. This gives users, external auditors, and other stakeholders time to review and react if necessary, building trust in the protocol's governance.
2.  **Internal Security Layer:** The delay acts as a critical security buffer. If the administrative `AdminCap` were ever compromised, the attacker could not immediately drain funds. The creation of a malicious withdrawal ticket would be a public event, giving our team and the community a window of opportunity to take corrective action.
