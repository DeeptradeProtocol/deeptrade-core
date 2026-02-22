import { Transaction } from "@mysten/sui/transactions";
import { TRADING_FEE_CONFIG_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { createPoolFeeConfigTx } from "./utils/createPoolFeeConfigTx";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { defaultFeesConfig } from "../fee-config";

// Read from UPDATE_FEES_TICKETS env, throw if empty or invalid
const ticketsEnv = process.env.UPDATE_FEES_TICKETS;
if (!ticketsEnv) {
  throw new Error("UPDATE_FEES_TICKETS environment variable is required.");
}

const TICKETS_OBJECT_IDS: string[] = ticketsEnv
  .split(",")
  .map((id) => id.trim())
  .filter((id) => id.length > 0);

if (TICKETS_OBJECT_IDS.length === 0) {
  throw new Error("UPDATE_FEES_TICKETS environment variable must contain at least one ticket ID.");
}

const TICKET_OBJECT_ID = TICKETS_OBJECT_IDS[0];

// yarn ts-node examples/ticket/update-default-pool-fees.ts > update-default-pool-fees.log 2>&1
(async () => {
  if (!TRADING_FEE_CONFIG_OBJECT_ID) {
    console.error("❌ Please set TRADING_FEE_CONFIG_OBJECT_ID in constants.ts");
    process.exit(1);
  }

  console.warn(`Building transaction to update default pool fees using ticket ${TICKET_OBJECT_ID}`);

  const tx = new Transaction();

  const { tx: poolFeeConfigTx, poolFeeConfig } = createPoolFeeConfigTx({
    transaction: tx,
    params: defaultFeesConfig,
  });

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee::update_default_fees`,
    arguments: [
      tx.object(TRADING_FEE_CONFIG_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID),
      tx.object(poolFeeConfig),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
  });

  await buildAndLogMultisigTransaction(tx);
})();
