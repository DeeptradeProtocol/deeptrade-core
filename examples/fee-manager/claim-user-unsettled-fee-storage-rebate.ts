import { Transaction } from "@mysten/sui/transactions";
import { ADMIN_CAP_OBJECT_ID, DEEPTRADE_CORE_PACKAGE_ID, TREASURY_OBJECT_ID } from "../constants";
import { buildAndLogMultisigTransaction } from "../multisig/buildAndLogMultisigTransaction";
import { MULTISIG_CONFIG } from "../multisig/multisig";

const FEE_MANAGER_ID = "0x4cef4ff8a75cc0e926fa57c99a3477d92b829b3a26b21cde5ea8b64041b75fba";
const POOL_ID = "0xfacee57bc356dae0d9958c653253893dfb24e24e8871f53e69b7dccb3ffbf945";
const BALANCE_MANAGER_ID = "0xee7dbd70069a7a536fa1e259bcaa4f8ef8c0cb6f04c21fe0ac74321793d309ab";
const ORDER_ID = "1844692854115028871151501";
const BASE_COIN_TYPE = "0x3a304c7feba2d819ea57c3542d68439ca2c386ba02159c740f7b406e592c62ea::haedal::HAEDAL";
const QUOTE_COIN_TYPE = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC";
const FEE_COIN_TYPE = "0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC";

// yarn ts-node examples/fee-manager/claim-user-unsettled-fee-storage-rebate.ts > claim-user-unsettled-fee-storage-rebate.log 2>&1
(async () => {
  const tx = new Transaction();

  tx.moveCall({
    target: `${DEEPTRADE_CORE_PACKAGE_ID}::fee_manager::claim_user_unsettled_fee_storage_rebate_admin`,
    arguments: [
      tx.object(TREASURY_OBJECT_ID),
      tx.object(FEE_MANAGER_ID),
      tx.object(POOL_ID),
      tx.object(BALANCE_MANAGER_ID),
      tx.object(ADMIN_CAP_OBJECT_ID),
      tx.pure.u128(ORDER_ID),
      tx.pure.vector("vector<u8>", MULTISIG_CONFIG.publicKeysSuiBytes),
      tx.pure.vector("u8", MULTISIG_CONFIG.weights),
      tx.pure.u16(MULTISIG_CONFIG.threshold),
    ],
    typeArguments: [BASE_COIN_TYPE, QUOTE_COIN_TYPE, FEE_COIN_TYPE],
  });

  console.warn(`Building transaction to claim user unsettled fee storage rebate for order ${ORDER_ID}`);

  await buildAndLogMultisigTransaction(tx);
})();
