import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID, LOYALTY_PROGRAM_OBJECT_ID, ADMIN_CAP_OBJECT_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";

export function grantUserLevelTx(userAddress: string, level: number, transaction?: Transaction) {
  const tx = transaction ?? new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::grant_user_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.address(userAddress),
      tx.pure.u8(level),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  return tx;
}
