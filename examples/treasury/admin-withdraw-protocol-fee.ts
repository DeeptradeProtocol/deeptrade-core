import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";
import { Transaction } from "@mysten/sui/transactions";
import { getTreasuryBags } from "./utils/getWrapperBags";
import { processFeesBag } from "./utils/processFeeBag";

// yarn ts-node examples/treasury/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw all protocol fees`);
  const tx = new Transaction();

  const { protocolFeesBagId } = await getTreasuryBags();

  // Process coverage fees
  const { coinsMapByCoinType } = await processFeesBag(protocolFeesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  for (const coinType of coinTypes) {
    getWithdrawFeeTx({
      coinType: coinType,
      target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_protocol_fee`,
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
