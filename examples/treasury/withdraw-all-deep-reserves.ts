import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { getDeepReservesBalance } from "./utils/getDeepReservesBalance";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

// yarn ts-node examples/treasury/withdraw-all-deep-reserves.ts > withdraw-all-deep-reserves.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesRaw: amountToWithdraw, deepReserves: amountToWithdrawFormatted } = await getDeepReservesBalance();

  const withdrawnCoin = tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_deep_reserves`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u64(amountToWithdraw),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(MULTISIG_CONFIG.address));
  console.warn(`Building transaction to withdraw ${amountToWithdrawFormatted} DEEP`);

  await buildAndLogMultisigTransaction(tx);
})();
