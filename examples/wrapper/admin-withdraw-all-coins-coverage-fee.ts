import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";
import { getTreasuryBags } from "./utils/getTreasuryBags";
import { processFeesBag } from "./utils/processFeeBag";

// yarn ts-node examples/treasury/admin-withdraw-all-coins-coverage-fee.ts > admin-withdraw-all-coins-coverage-fee.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesBagId } = await getTreasuryBags();

  // Process coverage fees
  const { coinsMapByCoinType } = await processFeesBag(deepReservesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  console.warn(
    `Building transaction to withdraw coverage fees for ${coinTypes.length} coin types: ${coinTypes.join(", ")}`,
  );

  for (const coinType of coinTypes) {
    getWithdrawFeeTx({
      coinType,
      target: `${WRAPPER_PACKAGE_ID}::treasury::withdraw_deep_reserves_coverage_fee`,
      user: MULTISIG_CONFIG.address,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      transaction: tx,
      pks: MULTISIG_CONFIG.publicKeysSuiBytes,
      weights: MULTISIG_CONFIG.weights,
      threshold: MULTISIG_CONFIG.threshold,
    });
  }

  await buildAndLogMultisigTransaction(tx);
})();
