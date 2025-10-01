import { ADMIN_CAP_OBJECT_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { createTicketTx, TicketType } from "./utils/createTicketTx";

// yarn ts-node examples/ticket/create-ticket.ts > create-ticket.log 2>&1
(async () => {
  const ticketType = TicketType.UpdateDefaultFees;

  console.warn(`Building transaction to create ticket for ${ticketType}`);

  const { tx, ticket } = createTicketTx({
    ticketType,
    adminCapId: ADMIN_CAP_OBJECT_ID,
    multisigConfigId: MULTISIG_CONFIG_OBJECT_ID,
  });

  await buildAndLogMultisigTransaction(tx);
})();
