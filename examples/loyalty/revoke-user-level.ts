import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { DEEPTRADE_CORE_PACKAGE_ID, LOYALTY_ADMIN_CAP_OBJECT_ID, LOYALTY_PROGRAM_OBJECT_ID } from "../constants";

const USER_ADDRESS = ""; // Address of the user to revoke the level from

// Usage: yarn ts-node examples/loyalty/revoke-user-level.ts > revoke-user-level.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::revoke_user_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(LOYALTY_ADMIN_CAP_OBJECT_ID),
      tx.pure.address(USER_ADDRESS),
    ],
  });

  console.warn(`Executing transaction to revoke loyalty level from user ${USER_ADDRESS}`);

  // const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });
  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log("res:", JSON.stringify(res, null, 2));
})();
