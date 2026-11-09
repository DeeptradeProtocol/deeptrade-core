import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

// Fill after create_rebates_claimer_cap; take the shared object ID from the RebatesClaimerCapCreated event
const REBATES_CLAIMER_CAP_OBJECT_ID = "";
const NEW_OWNER = ""; // New owner of the rebates claimer cap

// Usage: yarn ts-node examples/fee-manager/update-rebates-claimer-cap-owner.ts > update-rebates-claimer-cap-owner.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee_manager::update_rebates_claimer_cap_owner`,
    arguments: [
      tx.object(REBATES_CLAIMER_CAP_OBJECT_ID),
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.address(NEW_OWNER),
    ],
  });

  console.warn(`Building transaction to update rebates claimer cap owner to ${NEW_OWNER}`);

  await buildAndLogMultisigTransaction(tx);
})();
