import { Transaction } from "@mysten/sui/transactions";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { grantUserLevelTx } from "./utils";

const USER_ADDRESSES: string[] = []; // Addresses of the users to grant the level to
const LEVEL = 1; // Level to grant to the users

// Usage: yarn ts-node examples/loyalty/grant-multiple-users-level.ts > grant-multiple-users-level.log 2>&1
(async () => {
  const tx = new Transaction();

  USER_ADDRESSES.forEach((userAddress) => {
    grantUserLevelTx(userAddress, LEVEL, tx);
  });

  console.warn(`Building transaction to grant users ${USER_ADDRESSES} loyalty level ${LEVEL}`);

  await buildAndLogMultisigTransaction(tx);
})();
