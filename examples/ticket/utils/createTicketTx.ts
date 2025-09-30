import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { DEEPTRADE_CORE_PACKAGE_ID, MULTISIG_CONFIG_OBJECT_ID } from "../../constants";

export enum TicketType {
  WithdrawDeepReserves = "WithdrawDeepReserves",
  WithdrawProtocolFee = "WithdrawProtocolFee",
  WithdrawCoverageFee = "WithdrawCoverageFee",
  UpdatePoolCreationProtocolFee = "UpdatePoolCreationProtocolFee",
  UpdateDefaultFees = "UpdateDefaultFees",
  UpdatePoolSpecificFees = "UpdatePoolSpecificFees",
}

export interface CreateTicketParams {
  ticketType: TicketType;
  adminCapId: string;
  multisigConfigId: string;
  transaction?: Transaction;
}

export function createTicketTx({ ticketType, adminCapId, multisigConfigId, transaction }: CreateTicketParams): {
  tx: Transaction;
  ticket: any;
} {
  const tx = transaction ?? new Transaction();

  // Get the ticket type using helper functions from Move
  const ticketTypeArg = tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::ticket::${getTicketTypeHelperFunction(ticketType)}`,
    arguments: [],
  });

  const ticket = tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::ticket::create_ticket`,
    arguments: [tx.object(multisigConfigId), tx.object(adminCapId), ticketTypeArg, tx.object(SUI_CLOCK_OBJECT_ID)],
  });

  return { tx, ticket };
}

function getTicketTypeHelperFunction(ticketType: TicketType): string {
  switch (ticketType) {
    case TicketType.WithdrawDeepReserves:
      return "withdraw_deep_reserves_ticket_type";
    case TicketType.WithdrawProtocolFee:
      return "withdraw_protocol_fee_ticket_type";
    case TicketType.WithdrawCoverageFee:
      return "withdraw_coverage_fee_ticket_type";
    case TicketType.UpdatePoolCreationProtocolFee:
      return "update_pool_creation_protocol_fee_ticket_type";
    case TicketType.UpdateDefaultFees:
      return "update_default_fees_ticket_type";
    case TicketType.UpdatePoolSpecificFees:
      return "update_pool_specific_fees_ticket_type";
    default:
      throw new Error(`Unknown ticket type: ${ticketType}`);
  }
}
