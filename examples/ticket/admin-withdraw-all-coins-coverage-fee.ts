import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./utils/getWithdrawFeeTx";
import { getTreasuryBags } from "../treasury/utils/getTreasuryBags";
import { processFeesBag } from "../treasury/utils/processFeeBag";

const TICKET_OBJECT_ID = "";

// yarn ts-node examples/ticket/admin-withdraw-all-coins-coverage-fee.ts > admin-withdraw-all-coins-coverage-fee.log 2>&1
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
      target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_deep_reserves_coverage_fee`,
      ticketId: TICKET_OBJECT_ID,
      user: MULTISIG_CONFIG.address,
      transaction: tx,
    });
  }

  await buildAndLogMultisigTransaction(tx);
})();
