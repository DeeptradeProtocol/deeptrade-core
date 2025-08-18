import { coinWithBalance, Transaction } from "@mysten/sui/transactions";
import { keypair, provider } from "../common";
import { DEEP_COIN_TYPE, DEEP_DECIMALS, TREASURY_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";

// How many DEEP tokens to deposit (in human-readable format)
const DEEP_AMOUNT = 100;

// Convert human-readable amount to raw amount
const rawAmount = DEEP_AMOUNT * 10 ** DEEP_DECIMALS;

// yarn ts-node examples/treasury/deposit-into-reserves.ts > deposit-into-reserves.log 2>&1
(async () => {
  const coin = coinWithBalance({ balance: rawAmount, type: DEEP_COIN_TYPE });

  const tx = new Transaction();

  // Call the deposit function with our split coin
  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::deposit_into_reserves`,
    arguments: [tx.object(TREASURY_OBJECT_ID), coin],
  });

  const res = await provider.signAndExecuteTransaction({ transaction: tx, signer: keypair });

  console.debug(res);
})();
