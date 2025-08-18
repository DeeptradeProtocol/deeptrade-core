import { Transaction } from "@mysten/sui/transactions";
import { TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { getDeepReservesBalance } from "../treasury/utils/getDeepReservesBalance";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

const TICKET_OBJECT_ID = "";

// yarn ts-node examples/ticket/withdraw-all-deep-reserves.ts > withdraw-all-deep-reserves.log 2>&1
(async () => {
  const tx = new Transaction();

  const { deepReservesRaw: amountToWithdraw, deepReserves: amountToWithdrawFormatted } = await getDeepReservesBalance();

  const withdrawnCoin = tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_deep_reserves`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID),
      tx.pure.u64(amountToWithdraw),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(MULTISIG_CONFIG.address));
  console.warn(`Building transaction to withdraw ${amountToWithdrawFormatted} DEEP`);

  await buildAndLogMultisigTransaction(tx);
})();
