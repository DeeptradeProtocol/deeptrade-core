import { Transaction } from "@mysten/sui/transactions";
import {
  ADMIN_CAP_OBJECT_ID,
  DEEPTRADE_CORE_PACKAGE_ID,
  LOYALTY_ADMIN_CAP_OBJECT_ID,
  MULTISIG_CONFIG_OBJECT_ID,
} from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const NEW_OWNER = ""; // New owner of the loyalty admin cap

// Usage: yarn ts-node examples/loyalty/update-loyalty-admin-cap-owner.ts > update-loyalty-admin-cap-owner.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::update_loyalty_admin_cap_owner`,
    arguments: [
      tx.object(LOYALTY_ADMIN_CAP_OBJECT_ID),
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.address(NEW_OWNER),
    ],
  });

  console.warn(`Building transaction to update loyalty admin cap owner to ${NEW_OWNER}`);

  await buildAndLogMultisigTransaction(tx);
})();
