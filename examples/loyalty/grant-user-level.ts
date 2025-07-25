import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, LOYALTY_PROGRAM_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";

const USER_ADDRESS = ""; // Address of the user to grant the level to
const LEVEL = 1; // Level to grant to the user

// Usage: yarn ts-node examples/loyalty/grant-user-level.ts > grant-user-level.log 2>&1
(async () => {
  const tx = new Transaction();

  grantUserLevelTx(USER_ADDRESS, LEVEL, tx);

  console.warn(`Building transaction to grant user ${USER_ADDRESS} loyalty level ${LEVEL}`);

  await buildAndLogMultisigTransaction(tx);
})();

export function grantUserLevelTx(userAddress: string, level: number, transaction?: Transaction) {
  const tx = transaction ?? new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::grant_user_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.address(userAddress),
      tx.pure.u8(level),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  return tx;
}
