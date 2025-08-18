import { Transaction } from "@mysten/sui/transactions";
import { TREASURY_OBJECT_ID } from "../../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

export function getWithdrawFeeTx({
  coinType,
  target,
  user,
  ticketId,
  transaction,
}: {
  coinType: string;
  target: string;
  user: string;
  ticketId: string;
  transaction?: Transaction;
}): Transaction {
  const tx = transaction ?? new Transaction();

  const withdrawnCoin = tx.moveCall({
    target,
    arguments: [tx.object(TREASURY_OBJECT_ID), tx.object(ticketId), tx.object(SUI_CLOCK_OBJECT_ID)],
    typeArguments: [coinType],
  });

  tx.transferObjects([withdrawnCoin], tx.pure.address(user));

  return tx;
}
