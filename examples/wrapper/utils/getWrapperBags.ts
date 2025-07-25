import { provider } from "../../common";
import { WRAPPER_OBJECT_ID } from "../../constants";

export async function getTreasuryBags() {
  // Fetch the treasury object using its ID
  const treasuryObjectResponse = await provider.getObject({
    id: WRAPPER_OBJECT_ID,
    options: { showContent: true },
  });

  // Extract the object data from the response
  if (!treasuryObjectResponse.data?.content || treasuryObjectResponse.data.content.dataType !== "moveObject") {
    throw new Error("Could not fetch treasury object data");
  }

  const treasuryObject = treasuryObjectResponse.data.content.fields;

  // Get the bag IDs for both fee types
  const deepReservesBagId = (treasuryObject as any).deep_reserves_coverage_fees?.fields?.id?.id;
  const protocolFeesBagId = (treasuryObject as any).protocol_fees?.fields?.id?.id;

  if (!deepReservesBagId) {
    throw new Error("Could not find deep_reserves_coverage_fees bag ID");
  }

  if (!protocolFeesBagId) {
    throw new Error("Could not find protocol_fees bag ID");
  }

  return { deepReservesBagId, protocolFeesBagId };
}
