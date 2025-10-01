import { Transaction } from "@mysten/sui/transactions";
import {
  ADMIN_CAP_OBJECT_ID,
  DEEPTRADE_CORE_PACKAGE_ID,
  MULTISIG_CONFIG_OBJECT_ID,
  TREASURY_OBJECT_ID,
} from "../../constants";
import { buildAndLogMultisigTransaction } from "../../multisig/buildAndLogMultisigTransaction";

// Set the version to enable here
const VERSION = 2;

// Usage: yarn ts-node examples/treasury/versions/enable-version.ts > enable-version.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::enable_version`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u16(VERSION),
    ],
  });

  console.warn(`Building transaction to enable version ${VERSION}`);

  await buildAndLogMultisigTransaction(tx);
})();
