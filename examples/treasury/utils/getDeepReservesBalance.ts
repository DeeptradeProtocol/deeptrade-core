import { bcs } from "@mysten/sui/bcs";
import { Transaction } from "@mysten/sui/transactions";
import { DUMMY_PLACEHOLDER_ADDRESS } from "../../common";
import { provider } from "../../provider";
import { DEEP_DECIMALS, TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../../constants";

export async function getDeepReservesBalance() {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::deep_reserves`,
    arguments: [tx.object(TREASURY_OBJECT_ID)],
  });

  const res = await provider.devInspectTransactionBlock({
    sender: DUMMY_PLACEHOLDER_ADDRESS,
    transactionBlock: tx,
  });

  const { results } = res;

  if (!results || results.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No results found");
  }

  const { returnValues } = results[0];

  if (!returnValues || returnValues.length !== 1) {
    throw new Error("[getDeepReservesBalanceInfo] No return values found");
  }

  const deepReservesValueRaw = returnValues[0][0];
  const deepReservesValueDecoded = bcs.u64().parse(new Uint8Array(deepReservesValueRaw));
  const deepReservesValue = +deepReservesValueDecoded / 10 ** DEEP_DECIMALS;

  return {
    deepReserves: deepReservesValue.toString(),
    deepReservesRaw: deepReservesValueDecoded,
  };
}
