import { Transaction } from "@mysten/sui/transactions";
import {
  ADMIN_CAP_OBJECT_ID,
  DEEPTRADE_CORE_PACKAGE_ID,
  MULTISIG_CONFIG_OBJECT_ID,
  TREASURY_OBJECT_ID,
} from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const FEE_MANAGER_ID = "0x4cef4ff8a75cc0e926fa57c99a3477d92b829b3a26b21cde5ea8b64041b75fba";
const FEE_COIN_TYPE = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC";

// yarn ts-node examples/fee-manager/claim-protocol-unsettled-fee-storage-rebate.ts > claim-protocol-unsettled-fee-storage-rebate.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee_manager::claim_protocol_unsettled_fee_storage_rebate_admin`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(FEE_MANAGER_ID),
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
    ],
    typeArguments: [FEE_COIN_TYPE],
  });

  console.warn(
    `Building transaction to claim protocol unsettled fee storage rebate for fee coin type ${FEE_COIN_TYPE}`,
  );

  await buildAndLogMultisigTransaction(tx);
})();
