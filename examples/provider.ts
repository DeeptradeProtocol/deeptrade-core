import { SuiClient } from "@mysten/sui/client";

export const suiProviderUrl = "https://fullnode.mainnet.sui.io";
export const provider = new SuiClient({ url: suiProviderUrl });
