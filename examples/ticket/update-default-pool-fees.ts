import { Transaction } from "@mysten/sui/transactions";
import { TRADING_FEE_CONFIG_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID } from "../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { createPoolFeeConfigTx } from "./utils/createPoolFeeConfigTx";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";

const TICKET_OBJECT_ID = "";

const NEW_FEE_CONFIG = {
  deepFeeTypeTakerRate: 2_000_000,
  deepFeeTypeMakerRate: 1_000_000,
  inputCoinFeeTypeTakerRate: 2_000_000,
  inputCoinFeeTypeMakerRate: 1_000_000,
  maxDeepFeeCoverageDiscountRate: 1_000_000_000,
};

// yarn ts-node examples/timelock-examples/update-default-pool-fees.ts > update-default-pool-fees.log 2>&1
(async () => {
  if (!TICKET_OBJECT_ID) {
    console.error("❌ Please set TICKET_OBJECT_ID from the ticket creation step");
    process.exit(1);
  }

  if (!TRADING_FEE_CONFIG_OBJECT_ID) {
    console.error("❌ Please set TRADING_FEE_CONFIG_OBJECT_ID in constants.ts");
    process.exit(1);
  }

  console.warn(
    `Building transaction to update default pool fees to ${NEW_FEE_CONFIG}% using ticket ${TICKET_OBJECT_ID}`,
  );

  const tx = new Transaction();

  const { tx: poolFeeConfigTx, poolFeeConfig } = createPoolFeeConfigTx({
    transaction: tx,
    params: NEW_FEE_CONFIG,
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
