import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getTreasuryBags } from "../treasury/utils/getTreasuryBags";
import { processFeesBag } from "../treasury/utils/processFeeBag";
import { createTicketTx, TicketType } from "./utils/createTicketTx";

// yarn ts-node examples/ticket/create-multiple-tickets-withdraw-protocol-fees.ts > create-multiple-tickets-withdraw-protocol-fees.log 2>&1
(async () => {
  const ticketType = TicketType.WithdrawProtocolFee;
  const { protocolFeesBagId } = await getTreasuryBags();

  // Process coverage fees
  const { coinsMapByCoinType } = await processFeesBag(protocolFeesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  console.debug(`Building transaction to create tickets for ${ticketType} for ${coinTypes.length} coin types`);
  const tx = new Transaction();

  for (const coinType of coinTypes) {
    console.debug(`Creating ticket for withdrawing protocol fees for ${coinType}`);

    createTicketTx({
      transaction: tx,
      ticketType,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      multisigConfigId: MULTISIG_CONFIG_OBJECT_ID,
    });
  }

  await buildAndLogMultisigTransaction(tx);
})();
