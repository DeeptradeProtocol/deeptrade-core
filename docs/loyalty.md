# Loyalty Program

## Overview

The Loyalty Program rewards active users with discounts on trading fees. Users can be assigned different loyalty levels, each providing a specific discount percentage on protocol fees. This encourages user engagement and provides benefits to regular traders.

User loyalty levels are fully determined by the protocol governance (admin). The system is designed to be centrally managed to ensure fair and strategic distribution of loyalty benefits.

## Fee Calculation

When a user places an order, the system calculates their total discount rate:

```
// Ensures total discount doesn't exceed 100%
total_discount_rate = min(
    deep_fee_coverage_discount_rate + loyalty_discount_rate,
    100%
)
```

Where:

- `deep_fee_coverage_discount_rate`: Based on how much DEEP the user provides vs. takes from reserves
- `loyalty_discount_rate`: The user's loyalty level discount

## Administration

All actions with loyalty levels - creating levels, granting them to users, and revoking them - can only be performed by administrators with multisig approval. This ensures the system remains secure and controlled.

## Integration with Trading

The loyalty program integrates with the trading system in several places:

### Order Creation

When creating orders, the system:

1. Gets the user's loyalty discount rate
2. Combines it with the DEEP fee coverage discount
3. Applies the total discount to protocol fees

### Fee Estimation

The system estimates fees including loyalty discounts by:

- Combining loyalty discount with DEEP coverage discount
- Ensuring total discount doesn't exceed 100%
- Applying discount to protocol fees

## Key Rules

- Users can only have one loyalty level at a time
- Levels cannot be removed if they have members
- All administrative actions require multisig approval
