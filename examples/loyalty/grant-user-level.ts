import { Transaction } from "@mysten/sui/transactions";
import { keypair } from "../common";
import { grantUserLevelTx } from "./utils";
import { provider } from "../provider";

const USER_ADDRESS = ""; // Address of the user to grant the level to
const LEVEL = 1; // Level to grant to the user

// Usage: yarn ts-node examples/loyalty/grant-user-level.ts > grant-user-level.log 2>&1
(async () => {
  const tx = new Transaction();

  grantUserLevelTx(USER_ADDRESS, LEVEL, tx);

  console.warn(`Executing transaction to grant user ${USER_ADDRESS} loyalty level ${LEVEL}`);

  // const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });
  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log("res:", JSON.stringify(res, null, 2));
})();
