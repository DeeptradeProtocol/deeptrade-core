import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

// yarn ts-node examples/pool/create-pool-creation-config.ts
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::pool::create_pool_creation_config`,
    arguments: [tx.object(ADMIN_CAP_OBJECT_ID)],
  });

  await buildAndLogMultisigTransaction(tx);
})();
