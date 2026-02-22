import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_CONFIG_OBJECT_ID, MULTISIG_ADMIN_CAP_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";

// Usage: npx tsx examples/multisig/initialize-multisig-config.ts > initialize-multisig-config.log 2>&1
(async () => {
  const { publicKeysSuiBytes, weights, threshold, address } = MULTISIG_CONFIG;

  console.warn(`Building transaction to initialize multisig config`);
  console.warn(`- Multisig address: ${address}`);
  console.warn(`- Signers: ${publicKeysSuiBytes.length}`);
  console.warn(`- Weights: ${JSON.stringify(weights)}`);
  console.warn(`- Threshold: ${threshold}`);

  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::multisig_config::initialize_multisig_config`,
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
