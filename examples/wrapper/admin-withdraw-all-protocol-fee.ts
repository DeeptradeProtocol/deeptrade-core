import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import {
  ADMIN_CAP_OBJECT_ID,
  DEEP_COIN_TYPE,
  SUI_COIN_TYPE,
  WRAPPER_PACKAGE_ID,
} from "../constants";
import { getWithdrawFeeTx } from "./getWithdrawFeeTx";
import { getWrapperBags } from "./utils/getWrapperBags";
import { processFeesBag } from "./utils/processFeeBag";

// yarn ts-node examples/wrapper/admin-withdraw-protocol-fee.ts > admin-withdraw-protocol-fee.log 2>&1
(async () => {
  const tx = new Transaction();
  const { protocolFeesBagId } = await getWrapperBags();
  const { coinsMapByCoinType } = await processFeesBag(protocolFeesBagId);
  const coinTypes = Object.keys(coinsMapByCoinType);

  for (const coinType of coinTypes) {
    getWithdrawFeeTx({
      coinType,
      target: `${WRAPPER_PACKAGE_ID}::wrapper::admin_withdraw_protocol_fee_v2`,
      user,
      adminCapId: ADMIN_CAP_OBJECT_ID,
      transaction: tx,
    });
  }

  const res = await provider.signAndExecuteTransaction({
    transaction: tx,
    signer: keypair,
  });

  console.log(res);
})();
