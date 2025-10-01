import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_ADMIN_CAP_OBJECT_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { MultisigConfig } from "../multisig/types";

const NEW_PUBLIC_KEYS: MultisigConfig["publicKeysSuiBytes"] = [];
const NEW_WEIGHTS: MultisigConfig["weights"] = [];
const NEW_THRESHOLD: MultisigConfig["threshold"] = 0;

// yarn ts-node examples/multisig-config/initialize-multisig-config.ts > initialize-multisig-config.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::multisig_config::initialize_multisig_config`,
    arguments: [
      tx.object(MULTISIG_CONFIG_OBJECT_ID),
      tx.object(MULTISIG_ADMIN_CAP_OBJECT_ID),
      tx.pure.vector("vector<u8>", NEW_PUBLIC_KEYS),
      tx.pure.vector("u8", NEW_WEIGHTS),
      tx.pure.u16(NEW_THRESHOLD),
    ],
  });

  console.warn(`Executing transaction to initialize multisig config`);

  // const res = await provider.devInspectTransactionBlock({ transactionBlock: tx, sender: user });
  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.log("res:", JSON.stringify(res, null, 2));
})();
