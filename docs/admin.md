# Admin Capabilities

The `deeptrade-core` package is managed by 2 administrative capabilities: `AdminCap` and `LoyaltyAdminCap`.
To balance security with operational flexibility, these roles create a tiered system of authority:

- **`AdminCap`**: The core capability for all sensitive protocol functions. It is protected by a mandatory on-chain multisig enforcement, with an additional time-lock for the most critical actions. See our [Multisig](./multisig.md) document for more details.
- **`LoyaltyAdminCap`**: A delegated capability designed for routine, low-risk operations like managing individual user loyalty levels.

## 1. Direct Operations

For operations that are considered lower-risk or require immediate execution for operational flexibility and emergency response, authorization is granted directly via the `AdminCap`.

### Operations

- **Version Management** (`treasury.move`):
  - `enable_version`: Enables a new package version.
  - `disable_version`: Permanently disables an old package version.
- **Loyalty Program Management** (`loyalty.move`):
  - `add_loyalty_level` / `remove_loyalty_level`: Manages the available loyalty tiers.
  - `update_loyalty_admin_cap_owner`: Transfers ownership of the `LoyaltyAdminCap`.
- **Fees Management** (`fee_manager.move`):
  - `claim_user_unsettled_fee_storage_rebate_admin`: Claims storage rebate for a user's settled fee.
  - `claim_protocol_unsettled_fee_storage_rebate_admin`: Claims storage rebate for a settled protocol fee.

### Design Motivation

- **Emergency Response:** Versioning functions do not use a timelock to allow for rapid response in case of a critical bug or an issue with a dependency like the DeepBook protocol. This agility is crucial to protect the protocol and its users, as detailed in our [Versioning Strategy](./versioning.md).
- **Operational Flexibility:** The loyalty program is designed to be managed dynamically. We consider these operations to be low-risk, as the primary impact is on user fee discounts rather than a direct risk to locked funds. This flexibility allows us to manage the program efficiently without the delay of a timelock.
- **System Maintenance:** Administrative functions for claiming storage rebates are low-risk cleanup operations. They do not move user or protocol funds but instead recover storage costs from objects that are no longer in use. A timelock for such routine maintenance would add unnecessary overhead.

---

## 2. Timelocked Operations (`AdminTicket`)

For more sensitive operations, especially those involving the movement of funds, we introduce a mandatory timelock mechanism through the use of an `AdminTicket`.

An administrator must first create a ticket for a specific action by calling `ticket::create_ticket`. This action is publicly logged as a Sui event. The ticket can only be "consumed" to execute the intended action after a `TICKET_DELAY_DURATION` (2 days) has passed and before it expires after `TICKET_ACTIVE_DURATION` (3 days).

### Operations

- **Fund Withdrawal** (`treasury.move`):
  - `withdraw_deep_reserves`: Withdraws DEEP tokens from the protocol's main reserves.
  - `withdraw_protocol_fee`: Withdraws collected protocol fees for a specific coin type.
  - `withdraw_coverage_fee`: Withdraws collected coverage fees for a specific coin type.
- **Fee Configuration** (`fee.move`, `pool.move`):
  - `update_pool_creation_protocol_fee`: Changes the protocol fee required to create a new pool.
  - `update_default_fees`: Changes the global, default trading fee configuration.
  - `update_pool_specific_fees`: Sets or updates a custom trading fee configuration for a specific pool.

### Design Motivation

1.  **Observability and Trust:** The timelock system provides transparency. By emitting a `TicketCreated` event with a specific `ticket_type`, we signal our intent for sensitive actions to the community in advance. This gives users, external auditors, and other stakeholders time to review and react if necessary, building trust in the protocol's governance.
2.  **Internal Security Layer:** The delay acts as a critical security buffer. If the administrative `AdminCap` were ever compromised, the attacker could not immediately drain funds. The creation of a malicious withdrawal ticket would be a public event, giving our team and the community a window of opportunity to take corrective action.

---

## 3. Loyalty Admin Operations (`LoyaltyAdminCap`)

The `LoyaltyAdminCap` is a specialized capability for managing user-specific loyalty levels. It allows a designated address to perform these routine actions without requiring a multisig transaction for each one. This provides operational flexibility for a low-risk, high-frequency task.

Crucially, the multisig wallet retains ultimate control, as it can transfer ownership of the `LoyaltyAdminCap` at any time using the core `AdminCap`.

### Operations

- **User Loyalty Management** (`loyalty.move`):
  - `grant_user_level`: Assigns a loyalty tier to a specific user.
  - `revoke_user_level`: Removes a loyalty tier from a specific user.
