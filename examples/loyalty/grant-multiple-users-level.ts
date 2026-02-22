import { Transaction } from "@mysten/sui/transactions";
import { keypair } from "../common";
import { grantUserLevelTx } from "./utils";
import { provider } from "../provider";

const USER_ADDRESSES: string[] = []; // Addresses of the users to grant the level to
const LEVEL = 1; // Level to grant to the users

// Usage: yarn ts-node examples/loyalty/grant-multiple-users-level.ts > grant-multiple-users-level.log 2>&1
(async () => {
  const tx = new Transaction();

  USER_ADDRESSES.forEach((userAddress) => {
    grantUserLevelTx(userAddress, LEVEL, tx);
  });

  console.warn(`Executing transaction to grant users ${USER_ADDRESSES} loyalty level ${LEVEL}`);

  // const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });
  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log("res:", JSON.stringify(res, null, 2));
})();
