import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

export const suiProviderUrl = "https://fullnode.mainnet.sui.io";
export const provider = new SuiClient({ url: suiProviderUrl });

/**
 * A randomly generated Sui address used as a placeholder for read-only operations.
 *
 * @note Use this ONLY for `devInspectTransactionBlock` or dry-runs where a sender
 * address is required but no actual signing/gas payment occurs.
 * @warning Never send real assets to this address as the private key is not persisted.
 */
export const DUMMY_PLACEHOLDER_ADDRESS = new Ed25519Keypair().getPublicKey().toSuiAddress();
