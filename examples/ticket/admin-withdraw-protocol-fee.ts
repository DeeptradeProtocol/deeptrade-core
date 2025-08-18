import { DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./utils/getWithdrawFeeTx";
import { Transaction } from "@mysten/sui/transactions";
import { getTreasuryBags } from "../treasury/utils/getTreasuryBags";
import { processFeesBag } from "../treasury/utils/processFeeBag";

// Put all ticket objects ids for each coin type respectively
const TICKETS_OBJECT_IDS: string[] = [];

// yarn ts-node examples/ticket/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw all protocol fees`);
  const tx = new Transaction();

  const { protocolFeesBagId } = await getTreasuryBags();

  // Process coverage fees
  const { coinsMapByCoinType } = await processFeesBag(protocolFeesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  coinTypes.forEach((coinType, index) => {
    getWithdrawFeeTx({
      coinType: coinType,
      target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_protocol_fee`,
      ticketId: TICKETS_OBJECT_IDS[index],
      user: MULTISIG_CONFIG.address,
      transaction: tx,
    });
  });

  await buildAndLogMultisigTransaction(tx);
})();
