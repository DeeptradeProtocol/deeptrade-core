import "dotenv/config";
import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_CONFIG_OBJECT_ID, MULTISIG_ADMIN_CAP_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { SIGNATURE_FLAG_TO_SCHEME } from "@mysten/sui/cryptography";

// --- NEW multisig config comes from standard MULTISIG_* env vars (loaded by multisig.ts) ---
const { publicKeysSuiBytes, publicKeys, weights, threshold, address } = MULTISIG_CONFIG;

// Usage: npx tsx examples/multisig/update-multisig-config.ts > update-multisig-config.log 2>&1
(async () => {
  console.warn(`Building transaction to update multisig config`);
  console.warn(`\nNew multisig config:`);
  console.warn(`- Address: ${address}`);
  console.warn(`- Signers: ${publicKeys.length}`);
  console.warn(`- Weights: ${JSON.stringify(weights)}`);
  console.warn(`- Threshold: ${threshold}`);
  publicKeys.forEach((pk, i) => {
    const scheme = SIGNATURE_FLAG_TO_SCHEME[pk.flag() as keyof typeof SIGNATURE_FLAG_TO_SCHEME];
    console.warn(`  - Signer ${i + 1}: ${pk.toSuiAddress()} (${scheme}, weight: ${weights[i]})`);
  });

  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::multisig_config::update_multisig_config`,
    arguments: [
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(MULTISIG_ADMIN_CAP_OBJECT_ID),
      tx.pure.vector("vector<u8>", publicKeysSuiBytes),
      tx.pure.vector("u8", weights),
      tx.pure.u16(threshold),
    ],
  });

  await buildAndLogMultisigTransaction(tx);
})();
