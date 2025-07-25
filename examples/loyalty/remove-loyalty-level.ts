import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, LOYALTY_PROGRAM_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";

const LEVEL = 2; // Level ID to remove (must have no members)

// Usage: yarn ts-node examples/loyalty/remove-loyalty-level.ts > remove-loyalty-level.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::remove_loyalty_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u8(LEVEL),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to remove loyalty level ${LEVEL}`);

  await buildAndLogMultisigTransaction(tx);
})();
