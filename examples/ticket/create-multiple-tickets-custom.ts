import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, MULTISIG_CONFIG_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { createTicketTx, TicketType } from "./utils/createTicketTx";

(async () => {
  // Read inputs fed by GitHub Actions
  const ticketCounts = {
    [TicketType.UpdateDefaultFees]: Number(process.env.COUNT_UPDATE_DEFAULT_FEES || 0),
    [TicketType.UpdatePoolSpecificFees]: Number(process.env.COUNT_UPDATE_POOL_SPECIFIC_FEES || 0),
    [TicketType.WithdrawDeepReserves]: Number(process.env.COUNT_WITHDRAW_DEEP_RESERVES || 0),
    [TicketType.WithdrawProtocolFee]: Number(process.env.COUNT_WITHDRAW_PROTOCOL_FEE || 0),
    [TicketType.WithdrawCoverageFee]: Number(process.env.COUNT_WITHDRAW_COVERAGE_FEE || 0),
    [TicketType.UpdatePoolCreationProtocolFee]: Number(process.env.COUNT_UPDATE_POOL_CREATION_FEE || 0),
  };

  // Flatten the counts into an array of ticket types to create
  const ticketsToCreate = Object.entries(ticketCounts).flatMap(([typeStr, count]) =>
    Array(count).fill(typeStr as TicketType),
  );

  if (ticketsToCreate.length === 0) {
    console.error("❌ No tickets specified! Aborting.");
    return;
  }

  console.log("🎟️ Assembling Custom Tickets Transaction for:");
  Object.entries(ticketCounts).forEach(([typeStr, count]) => {
    if (count > 0) console.log(` - Adding ${count}x [${typeStr}]`);
  });

  const tx = new Transaction();

  ticketsToCreate.forEach((ticketType) => {
    createTicketTx({
      transaction: tx,
      ticketType,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      multisigConfigId: MULTISIG_CONFIG_OBJECT_ID,
    });
  });

  console.log(`\n✅ Transaction populated with ${ticketsToCreate.length} total tickets.`);
  await buildAndLogMultisigTransaction(tx);
})();
