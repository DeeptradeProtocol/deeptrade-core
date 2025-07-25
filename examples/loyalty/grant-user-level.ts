import { Transaction } from "@mysten/sui/transactions";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { grantUserLevelTx } from "./utils";

const USER_ADDRESS = ""; // Address of the user to grant the level to
const LEVEL = 1; // Level to grant to the user

// Usage: yarn ts-node examples/loyalty/grant-user-level.ts > grant-user-level.log 2>&1
(async () => {
  const tx = new Transaction();

  grantUserLevelTx(USER_ADDRESS, LEVEL, tx);

  console.warn(`Building transaction to grant user ${USER_ADDRESS} loyalty level ${LEVEL}`);

  await buildAndLogMultisigTransaction(tx);
})();
