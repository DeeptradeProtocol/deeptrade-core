import { getTreasuryBags } from "./utils/getTreasuryBags";
import { processFeesBag } from "./utils/processFeeBag";
import { printFeeSummary } from "./utils/printFeeSummary";

// yarn ts-node examples/treasury/get-charged-fee-info.ts > charged-fee-info.log 2>&1
(async () => {
  const { deepReservesBagId, protocolFeesBagId } = await getTreasuryBags();

  // Process both fee types
  const deepReservesFees = await processFeesBag(deepReservesBagId);
  const protocolFees = await processFeesBag(protocolFeesBagId);

  // Print summaries
  printFeeSummary(
    "Deep Reserves Coverage Fees",
    deepReservesFees.coinsMapByCoinType,
    deepReservesFees.coinsMetadataMapByCoinType,
  );
  printFeeSummary("Protocol Fees", protocolFees.coinsMapByCoinType, protocolFees.coinsMetadataMapByCoinType);
})();
