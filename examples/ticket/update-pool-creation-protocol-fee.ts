import { Transaction } from "@mysten/sui/transactions";
import { DEEP_DECIMALS, POOL_CREATION_CONFIG_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

const TICKET_OBJECT_ID = "";

const NEW_FEE = 200 * 10 ** DEEP_DECIMALS; // 200 DEEP

// yarn ts-node examples/ticket/update-pool-creation-protocol-fee.ts
(async () => {
  console.warn(`Building transaction to update pool creation protocol fee to ${NEW_FEE / 10 ** DEEP_DECIMALS} DEEP`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::pool::update_pool_creation_protocol_fee`,
    arguments: [
      tx.object(POOL_CREATION_CONFIG_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID),
      tx.pure.u64(NEW_FEE),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  await buildAndLogMultisigTransaction(tx);
})();
