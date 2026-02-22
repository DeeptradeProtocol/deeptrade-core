import { Transaction } from "@mysten/sui/transactions";
import { DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { MULTISIG_CONFIG } from "../multisig/multisig";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { getWithdrawFeeTx } from "./utils/getWithdrawFeeTx";
import { getTreasuryBags } from "../treasury/utils/getTreasuryBags";
import { processFeesBag } from "../treasury/utils/processFeeBag";

// Read from TICKETS env, throw if empty or invalid
const ticketsEnv = process.env.TICKETS;
if (!ticketsEnv) {
  throw new Error("TICKETS environment variable is required.");
}

const TICKETS_OBJECT_IDS: string[] = ticketsEnv
  .split(",")
  .map((id) => id.trim())
  .filter((id) => id.length > 0);

if (TICKETS_OBJECT_IDS.length === 0) {
  throw new Error("TICKETS environment variable must contain at least one ticket ID.");
}

// yarn ts-node examples/ticket/admin-withdraw-all-coins-coverage-fee.ts > admin-withdraw-all-coins-coverage-fee.log 2>&1
(async () => {
  console.warn(`Building transaction to withdraw all coverage fees`);
  const tx = new Transaction();

  const { deepReservesBagId } = await getTreasuryBags();

  // Process coverage fees
  const { coinsMapByCoinType, coinsMetadataMapByCoinType } = await processFeesBag(deepReservesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  if (TICKETS_OBJECT_IDS.length < coinTypes.length) {
    console.warn(
      `\n⚠️  WARNING: You provided ${TICKETS_OBJECT_IDS.length} tickets, but there are ${coinTypes.length} coin types with fees.`,
    );
    console.warn(`Only the first ${TICKETS_OBJECT_IDS.length} coin types will be withdrawn.\n`);
  }

  const withdrawnCoins: string[] = [];

  for (let i = 0; i < coinTypes.length; i++) {
    const coinType = coinTypes[i];
    const ticketId = TICKETS_OBJECT_IDS[i];

    if (!ticketId) {
      // Stop if we run out of tickets
      break;
    }

    getWithdrawFeeTx({
      coinType: coinType,
      target: `${DEEPTRADE_CORE_PACKAGE_ID}::treasury::withdraw_coverage_fee`,
      ticketId: ticketId,
      user: MULTISIG_CONFIG.address,
      transaction: tx,
    });

    withdrawnCoins.push(coinType);
  }

  if (withdrawnCoins.length > 0) {
    console.log(`\n✅ Withdrawing coverage fees for the following ${withdrawnCoins.length} coins:`);
    withdrawnCoins.forEach((coinType) => {
      const amountRaw = coinsMapByCoinType[coinType];
      const metadata = coinsMetadataMapByCoinType[coinType];
      const amount = Number(amountRaw) / 10 ** metadata.decimals;
      console.log(` - ${metadata.symbol}: ${amount} (${amountRaw} raw)`);
    });
  } else {
    console.log(`\nℹ️  No coverage fees were added to the transaction.`);
  }

  const remainingCoins = coinTypes.slice(withdrawnCoins.length);
  if (remainingCoins.length > 0) {
    console.log(`\n⚠️  The following ${remainingCoins.length} coins will REMAIN in the bag (lack of tickets):`);
    remainingCoins.forEach((coinType) => {
      const amountRaw = coinsMapByCoinType[coinType];
      const metadata = coinsMetadataMapByCoinType[coinType];
      const amount = Number(amountRaw) / 10 ** metadata.decimals;
      console.log(` - ${metadata.symbol}: ${amount} (${amountRaw} raw)`);
    });
  }

  await buildAndLogMultisigTransaction(tx);
})();
