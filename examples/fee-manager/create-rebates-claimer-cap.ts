import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const OWNER = ""; // Address that will own the rebates claimer cap

// Usage: yarn ts-node examples/fee-manager/create-rebates-claimer-cap.ts > create-rebates-claimer-cap.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee_manager::create_rebates_claimer_cap`,
    arguments: [tx.object(MULTISIG_CONFIG_OBJECT_ID), tx.object(ADMIN_CAP_OBJECT_ID), tx.pure.address(OWNER)],
  });

  console.warn(`Building transaction to create rebates claimer cap for owner ${OWNER}`);

  await buildAndLogMultisigTransaction(tx);
})();
