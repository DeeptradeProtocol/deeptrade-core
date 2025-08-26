# Gas Consumption Analysis

Gas efficiency is a key design consideration, as it directly impacts user costs and the overall user experience.
We have conducted a rigorous gas consumption analysis for all primary protocol operations to validate our commitment to on-chain performance.

The measurements were performed using the `sui client replay-transaction` tool, which provides a precise breakdown of computation and storage fees. You can learn more about this tool in the [official Sui Replay CLI Documentation](https://docs.sui.io/references/cli/replay).

The following report details the gas costs for key user actions, providing transparency into the protocol's on-chain performance. These measurements reflect the engineering and optimization efforts invested to deliver a cost-effective trading experience.

## Gas Fee Formulas

The following formulas calculate the storage fees from both the validator's and the user's perspectives:

- **Validator Perspective**:

  $$
  \text{storage\_fee (validator)} = \text{old\_rebates\_sum} - \text{new\_rebates\_sum} - \text{non\_refundable\_storage\_fee}
  $$

- **User Perspective**:
  $$
  - \text{storage\_fee (user)} = \text{new\_rebates\_sum} - \text{old\_rebates\_sum} + \text{non\_refundable\_storage\_fee}
  $$

## Detailed Gas Cost Breakdown

1. Limit order Input fee + `FeeManager` creation: 0.009592372 SUI ([link](https://suivision.xyz/txblock/GDoM4UmKi2ajq4hNKkYhmnxRULRE9QJnCKXZtsyRAQoj))
   1. Computation fee: 0.000503 SUI (1,000 bucket)
   2. Storage fee: 0.009089372
   3. SUI
      1. `FeeManager` creation: 0.002204 SUI (non-reclaimable)
      2. `FeeManagerOwnerCap` creation: 0.0016568 SUI (non-reclaimable)
      3. `UserUnsettledFee` added: 0.0034352 SUI (reclaimable)
      4. `USDC` coin created: 0.0013224 SUI (reclaimable)
      5. `BigVector::Slice` modification (DeepBook): 0.000874 SUI
      6. `Account` dynamic field modification (DeepBook): 0.0001216 SUI
      7. Our storage fee: 0.0086184 SUI (44% non-reclaimable, 56% reclaimable)
      8. Sum: 0.009614 SUI
2. Limit order DEEP fee + `FeeManager` creation + some DeepBook creations: 0.01602828 SUI ([link](https://suivision.xyz/txblock/BksebW7bWL8sHFnbbfuziiavAnjtNsFfzK9TeDKSk5A9))
   1. Computation fee: 0.000503 SUI (1,000 bucket)
   2. Storage fee: 0.01552528 SUI
      1. `FeeManager` creation: 0.002204 SUI (non-reclaimable)
      2. `FeeManagerOwnerCap` creation: 0.0016568 SUI (non-reclaimable)
      3. `UserUnsettledFee` added: 0.00342 SUI (reclaimable)
      4. `SUI` coin created: 0.000988 SUI (reclaimable)
      5. `DEEP` coin created: 0.0013224 SUI (reclaimable)
      6. `BalanceKey` created (DeepBook): 0.0029108 SUI (reclaimable)
      7. `Account` df created (DeepBook): 0.0034048 SUI
      8. Our storage fee: 0.0095912 SUI (40% non-reclaimable, 60% reclaimable)
3. Limit order Input fee: 0.00444022 SUI ([link](https://suivision.xyz/txblock/6ioMWkqqsq56mrKjp64NwX9e4fomw6WfLbXhKjsmby3k))
   1. Computation fee: 0.0005 SUI (1,000 bucket)
   2. Storage fee: 0.00394022 SUI
      1. `UserUnsettledFee` added: 0.0034352 SUI (reclaimable)
      2. `USDC` coin created: 0.0013224 SUI (reclaimable)
      3. Our storage fee: 0.0047576 SUI (100% reclaimable)
4. Limit order DEEP fee + `ChargedFeeKey` creation coverage fees bag: 0.009408868 SUI ([link](https://suivision.xyz/txblock/Fmkg8MG3Ba3MnY9ktdmhu6KkczkmV38tLAnuPmzKYch))
   1. Computation fee: 0.001 SUI (2,000 bucket)
   2. Storage fee: 0.008408868 SUI
      1. `UserUnsettledFee` added: 0.0034352 SUI (reclaimable)
      2. `ChargedFeeKey` df for deep reserves coverage fee bag created: 0.00285 SUI (non-reclaimable, one-time operation for all users)
      3. `USDC` coin created: 0.0013224 SUI (reclaimable)
      4. `SUI` coin created: 0.000988 SUI (reclaimable)
      5. `BalanceKey` created (DeepBook): 0.0029108 SUI (reclaimable)
      6. Our storage fee: 0.0085956 SUI (66% reclaimable, 34% non-reclaimable, but one-time operation)
5. Limit order DEEP fee: 0.00920572 SUI ([link](https://suivision.xyz/txblock/5ctYuWs4o1U9izDAeKJ6aBMxrfKAPiq15DhKZs3oG3j4))
   1. Computation fee: 0.001 SUI (2,000 bucket)
   2. Storage fee: 0.00820572 SUI
      1. `UserUnsettledFee` added: 0.0034352 SUI (reclaimable)
      2. `USDC` coin created: 0.0013224 SUI (reclaimable)
      3. `SUI` coin created: 0.000988 SUI (reclaimable)
      4. `BalanceKey` created (DeepBook): 0.0029108 SUI (reclaimable)
      5. Our storage fee: 0.0057456 SUI (100% reclaimable)
6. Cancel order (2 `withdraw_all`): 0.001038456 SUI ([link](https://suivision.xyz/txblock/DbzcVefrRYNwSbhvAWG1oqnpcCa7MBPy1UwWRLht1rqA))
   1. Computation fee: 0.001 SUI (2,000 bucket)
   2. Storage fee: 0.000038456 SUI
      1. `SUI` coin created: 0.000988 SUI (reclaimable)
      2. x2 `USDC` coin created: 0.0026448 SUI (reclaimable)
      3. Our storage fee: 0.0036328 SUI (100% reclaimable)
7. Market order Input fee + withdraws: 0.003222696 SUI ([link](https://suivision.xyz/txblock/3VeqMiHv2pmnNBca8ByWpdVr1TLidMo6G1e4x2dzMgEk))
   1. Computation fee: 0.001 SUI (2,000 bucket)
   2. Storage fee: 0.002222696 SUI
      1. `SUI` coin created: 0.000988 SUI (reclaimable)
      2. `USDC` coin created: 0.0013224 SUI (reclaimable)
      3. Our storage fee: 0.0023104 SUI (100% reclaimable)
8. Market order DEEP fee + withdraws + `ProtocolUnsettledFeeKey` creation: 0.00767006 SUI ([link](https://suivision.xyz/txblock/9czYXigNM2SsfBCmyaCyjMbk7VMhNmvSXjwDFpjXv2Fw))
   1. Computation fee: 0.0015 SUI (3,000 bucket)
   2. Storage fee: 0.00617006 SUI
      1. x2 `SUI` coin created: 0.001976 SUI (reclaimable)
      2. x2 `USDC` coin created: 0.0026448 SUI (reclaimable)
      3. `ProtocolUnsettledFeeKey` created: 0.0029792 SUI (reclaimable)
      4. Our storage fee: 0.0076 SUI (100% reclaimable)
9. Swap 1 step: 0.006929372 SUI ([link](https://suivision.xyz/txblock/7LX5T8wgnWyBQqK5ocCN9qy5piFrPQBaAex33ok6Y5si))
   1. Computation fee: 0.0005 SUI (1,000 bucket)
   2. Storage fee: 0.006429372 SUI
      1. `SUI` coin created: 0.000988 SUI (reclaimable)
      2. `USDC` coin created: 0.0013224 SUI (reclaimable)
      3. `Account` df created (DeepBook): 0.0032832 SUI
      4. Our storage fee: 0.0023104 SUI (100% reclaimable)
10. Swap 2 steps: 0.014329716 SUI ([link](https://suivision.xyz/txblock/7ytNBkoZ4tCrAsNv8Xrpr9L7C5mJ76GP9DpksL8qmW2R))
    1. Computation fee: 0.001 SUI (2,000 bucket)
    2. Storage fee: 0.013329716 SUI
       1. `ProtocolUnsettledFeeKey` df created: 0.0032832 SUI (reclaimable)
       2. `SUI` coin created: 0.000988 SUI (reclaimable)
       3. `USDC` coin created: 0.0013224 SUI (reclaimable)
       4. `xBTC` coin created: 0.0013224 SUI (reclaimable)
       5. x2 `Account` df created (DeepBook): 0.0065664 SUI
       6. Our storage fee: 0.006916 SUI (100% reclaimable)
11. Brand new account, Limit order DEEP fee: 0.022343384 SUI ([link](https://suivision.xyz/txblock/FR7Br95gus25pT5HyKENKZ5ajF5rL8LhWugRXhQTmBQ2))
    1. Computation fee: 0.001 SUI (2,000 bucket)
    2. Storage fee: 0.021343384 SUI
       1. `FeeManager` created: 0.002204 SUI (non-reclaimable)
       2. `FeeManagerOwnerCap` created: 0.0016568 SUI (non-reclaimable)
       3. `UserUnsettledFee` created: 0.0034352 SUI (reclaimable)
       4. `SUI` coin created: 0.000988 SUI (reclaimable)
       5. `USDC` coin created: 0.0013224 SUI (reclaimable)
       6. `BalanceManager` created (DeepBook): 0.0022116 SUI (non-reclaimable)
       7. `TradeCap` created (DeepBook): 0.0016112 SUI (non-reclaimable)
       8. `Account` df created (DeepBook): 0.0034048 SUI (non-reclaimable)
       9. `BalanceKey` created (DeepBook): 0.0029108 SUI (reclaimable)
       10. Our storage fee: 0.0096064 SUI (60% reclaimable, 40% non-reclaimable)
