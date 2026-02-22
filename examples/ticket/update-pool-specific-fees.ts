import { Transaction } from "@mysten/sui/transactions";
import { TRADING_FEE_CONFIG_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { createPoolFeeConfigTx } from "./utils/createPoolFeeConfigTx";
import { poolSpecificFeesConfig } from "../fee-config";

// Read from UPDATE_FEES_TICKETS env, throw if empty or invalid
const ticketsEnv = process.env.UPDATE_FEES_TICKETS;
if (!ticketsEnv) {
  throw new Error("UPDATE_FEES_TICKETS environment variable is required.");
}

const TICKETS_OBJECT_IDS: string[] = ticketsEnv
  .split(",")
  .map((id) => id.trim())
  .filter((id) => id.length > 0);

if (TICKETS_OBJECT_IDS.length < poolSpecificFeesConfig.length) {
  throw new Error(
    `Not enough tickets provided! Found ${TICKETS_OBJECT_IDS.length} but need ${poolSpecificFeesConfig.length} for the pools defined in config.`,
  );
}

// yarn ts-node examples/ticket/update-pool-specific-fees.ts > update-pool-specific-fees.log 2>&1
(async () => {
  if (!TRADING_FEE_CONFIG_OBJECT_ID) {
    console.error("❌ Please set TRADING_FEE_CONFIG_OBJECT_ID in constants.ts");
    process.exit(1);
  }

  console.warn(`Building transaction to update fees for ${poolSpecificFeesConfig.length} pools...`);

  const tx = new Transaction();

  poolSpecificFeesConfig.forEach((pool, index) => {
    const ticketId = TICKETS_OBJECT_IDS[index];

    console.warn(` - Pool: ${pool.poolId} (Ticket: ${ticketId})`);

    const { poolFeeConfig } = createPoolFeeConfigTx({
      transaction: tx,
      params: pool.fees,
    });

    tx.moveCall({
      target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee::update_pool_specific_fees`,
      arguments: [
        tx.object(TRADING_FEE_CONFIG_OBJECT_ID),
        tx.object(ticketId),
        tx.object(pool.poolId),
        tx.object(poolFeeConfig),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
      typeArguments: [pool.baseCoin, pool.quoteCoin],
    });
  });

  await buildAndLogMultisigTransaction(tx);
})();
