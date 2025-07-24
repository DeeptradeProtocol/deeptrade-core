import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, LOYALTY_PROGRAM_OBJECT_ID, WRAPPER_PACKAGE_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { percentageInBillionths } from "../utils";

const LEVEL = 2; // Level ID to create
const FEE_DISCOUNT_PERCENTAGE = 50; // 50% discount rate
const FEE_DISCOUNT_RATE = percentageInBillionths(FEE_DISCOUNT_PERCENTAGE);

// Usage: yarn ts-node examples/loyalty/add-loyalty-level.ts > add-loyalty-level.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${WRAPPER_PACKAGE_ID}::loyalty::add_loyalty_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u8(LEVEL),
      tx.pure.u64(FEE_DISCOUNT_RATE),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  console.warn(`Building transaction to add loyalty level ${LEVEL} with ${FEE_DISCOUNT_PERCENTAGE}% fee discount`);

  await buildAndLogMultisigTransaction(tx);
})();
