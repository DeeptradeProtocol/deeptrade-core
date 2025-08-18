import { Transaction } from "@mysten/sui/transactions";
import { TRADING_FEE_CONFIG_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, SUI_COIN_TYPE, DEEP_COIN_TYPE } from "../constants";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { createPoolFeeConfigTx } from "./utils/createPoolFeeConfigTx";

const TICKET_OBJECT_ID = "";

// DEEP_SUI pool id
const POOL_ID = "0xb663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22";
const BASE_COIN_TYPE = DEEP_COIN_TYPE;
const QUOTE_COIN_TYPE = SUI_COIN_TYPE;

const NEW_FEE_CONFIG = {
  deepFeeTypeTakerRate: 0,
  deepFeeTypeMakerRate: 0,
  inputCoinFeeTypeTakerRate: 0,
  inputCoinFeeTypeMakerRate: 0,
  maxDeepFeeCoverageDiscountRate: 0,
};

// yarn ts-node examples/ticket/update-pool-specific-fees.ts > update-pool-specific-fees.log 2>&1
(async () => {
  if (!TICKET_OBJECT_ID) {
    console.error("❌ Please set TICKET_OBJECT_ID from the ticket creation step");
    process.exit(1);
  }

  if (!TRADING_FEE_CONFIG_OBJECT_ID) {
    console.error("❌ Please set TRADING_FEE_CONFIG_OBJECT_ID in constants.ts");
    process.exit(1);
  }

  if (!POOL_ID || !BASE_COIN_TYPE || !QUOTE_COIN_TYPE) {
    console.error("❌ Please set POOL_ID, BASE_COIN_TYPE and QUOTE_COIN_TYPE");
    process.exit(1);
  }

  console.warn(
    `Building transaction to update pool specific fees to ${NEW_FEE_CONFIG}% using
    ticket ${TICKET_OBJECT_ID} for pool ${POOL_ID},
    base coin ${BASE_COIN_TYPE} and quote coin ${QUOTE_COIN_TYPE}`,
  );

  const tx = new Transaction();

  const { tx: poolFeeConfigTx, poolFeeConfig } = createPoolFeeConfigTx({
    transaction: tx,
    params: NEW_FEE_CONFIG,
  });

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee::update_pool_specific_fees`,
    arguments: [
      tx.object(TRADING_FEE_CONFIG_OBJECT_ID),
      tx.object(TICKET_OBJECT_ID),
      tx.object(POOL_ID),
      tx.object(poolFeeConfig),
      tx.object(SUI_CLOCK_OBJECT_ID),
    ],
    typeArguments: [BASE_COIN_TYPE, QUOTE_COIN_TYPE],
  });

  await buildAndLogMultisigTransaction(tx);
})();
