import { Transaction } from "@mysten/sui/transactions";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const RECIPIENT = process.env.MULTISIG_ADMIN_CAP_HOLDER_ADDRESS;
if (!RECIPIENT) {
  throw new Error("MULTISIG_ADMIN_CAP_HOLDER_ADDRESS environment variable is required.");
}

// 0.1 SUI = 100_000_000 MIST (SUI has 9 decimals)
const AMOUNT_MIST = 0.1 * 10 ** 9;

// Usage: npx tsx examples/send-coins/send-sui.ts > send-sui.log 2>&1
(async () => {
  console.warn(`Building transaction to send 0.1 SUI to ${RECIPIENT}`);

  const tx = new Transaction();

  const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(AMOUNT_MIST)]);
  tx.transferObjects([coin], tx.pure.address(RECIPIENT));

  await buildAndLogMultisigTransaction(tx);
})();
