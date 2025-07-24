import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, LOYALTY_PROGRAM_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";

const USER_ADDRESS = ""; // Address of the user to revoke the level from

// Usage: yarn ts-node examples/loyalty/revoke-user-level.ts > revoke-user-level.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::loyalty::revoke_user_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.address(USER_ADDRESS),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to revoke loyalty level from user ${USER_ADDRESS}`);

  await buildAndLogMultisigTransaction(tx);
})();
