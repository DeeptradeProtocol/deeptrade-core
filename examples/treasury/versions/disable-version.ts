import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../../constants";
import { MULTISIG_CONFIG } from "../../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../../multisig/buildAndLogMultisigTransaction";

// Set the version to disable here
const VERSION = 1;

// Usage: yarn ts-node examples/treasury/versions/disable-version.ts > disable-version.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::disable_version`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u16(VERSION),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to disable version ${VERSION}`);

  await buildAndLogMultisigTransaction(tx);
})();
