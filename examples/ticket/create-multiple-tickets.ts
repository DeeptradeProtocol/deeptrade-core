import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { createTicketTx, TicketType } from "./utils/createTicketTx";

// yarn ts-node examples/timelock-examples/create-multiple-tickets.ts > create-multiple-tickets.log 2>&1
(async () => {
  const ticketTypes = [
    TicketType.UpdateDefaultFees,
    TicketType.UpdatePoolSpecificFees,
    TicketType.WithdrawDeepReserves,
    TicketType.WithdrawProtocolFee,
    TicketType.WithdrawCoverageFee,
    TicketType.UpdatePoolCreationProtocolFee,
  ];

  console.warn(`Building transaction to create tickets for ${ticketTypes.join(", ")}`);

  const tx = new Transaction();

  for (const ticketType of ticketTypes) {
    createTicketTx({
      transaction: tx,
      ticketType,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      pks: MULTISIG_CONFIG.publicKeysSuiBytes,
      weights: MULTISIG_CONFIG.weights,
      threshold: MULTISIG_CONFIG.threshold,
    });
  }

  await buildAndLogMultisigTransaction(tx);
})();
