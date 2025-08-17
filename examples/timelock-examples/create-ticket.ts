import { ADMIN_CAP_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { createTicketTx, TicketType } from "./utils/createTicketTx";

// yarn ts-node examples/timelock-examples/create-ticket.ts > create-ticket.log 2>&1
async () => {
  const ticketType = TicketType.UpdateDefaultFees;

  console.warn(`Building transaction to create ticket for ${ticketType}`);

  const { tx, ticket } = createTicketTx({
    ticketType,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    pks: MULTISIG_CONFIG.publicKeysSuiBytes,
    weights: MULTISIG_CONFIG.weights,
    threshold: MULTISIG_CONFIG.threshold,
  });

  await buildAndLogMultisigTransaction(tx);
};
