import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID, LOYALTY_ADMIN_CAP_OBJECT_ID, LOYALTY_PROGRAM_OBJECT_ID } from "../constants";

export function grantUserLevelTx(userAddress: string, level: number, transaction?: Transaction) {
  const tx = transaction ?? new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::loyalty::grant_user_level`,
    arguments: [
      tx.object(LOYALTY_PROGRAM_OBJECT_ID),
      tx.object(LOYALTY_ADMIN_CAP_OBJECT_ID),
      tx.pure.address(userAddress),
      tx.pure.u8(level),
    ],
  });

  return tx;
}
