import { Transaction, TransactionResult } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID } from "../../constants";

export interface PoolFeeConfigParams {
  deepFeeTypeTakerRate: number;
  deepFeeTypeMakerRate: number;
  inputCoinFeeTypeTakerRate: number;
  inputCoinFeeTypeMakerRate: number;
  maxDeepFeeCoverageDiscountRate: number;
}

export function createPoolFeeConfigTx({
  transaction,
  params,
}: {
  transaction?: Transaction;
  params: PoolFeeConfigParams;
}): {
  tx: Transaction;
  poolFeeConfig: TransactionResult;
} {
  const tx = transaction ?? new Transaction();

  const poolFeeConfig = tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee::new_pool_fee_config`,
    arguments: [
      tx.pure.u64(params.deepFeeTypeTakerRate),
      tx.pure.u64(params.deepFeeTypeMakerRate),
      tx.pure.u64(params.inputCoinFeeTypeTakerRate),
      tx.pure.u64(params.inputCoinFeeTypeMakerRate),
      tx.pure.u64(params.maxDeepFeeCoverageDiscountRate),
    ],
  });

  return { tx, poolFeeConfig };
}
