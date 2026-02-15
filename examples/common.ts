import "dotenv/config";

import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { hexStringToUint8Array, normalizeMnemonic } from "./utils";

if (!process.env.SUI_WALLET_SEED_PHRASE?.length && !process.env.SUI_WALLET_PRIVATE_KEY_ARRAY?.length) {
  throw new Error("Empty mnemonic or private key");
}

export const suiProviderUrl = "https://fullnode.mainnet.sui.io";
export const provider = new SuiClient({ url: suiProviderUrl });

export const mnemonic = normalizeMnemonic(process.env.SUI_WALLET_SEED_PHRASE ?? "");

export const keypair = process.env.SUI_WALLET_PRIVATE_KEY_ARRAY
  ? Ed25519Keypair.fromSecretKey(hexStringToUint8Array(process.env.SUI_WALLET_PRIVATE_KEY_ARRAY))
  : Ed25519Keypair.deriveKeypair(mnemonic);
export const user = keypair.getPublicKey().toSuiAddress();

/**
 * A randomly generated Sui address used as a placeholder for read-only operations.
 *
 * @note Use this ONLY for `devInspectTransactionBlock` or dry-runs where a sender
 * address is required but no actual signing/gas payment occurs.
 * @warning Never send real assets to this address as the private key is not persisted.
 */
export const DUMMY_PLACEHOLDER_ADDRESS = new Ed25519Keypair().getPublicKey().toSuiAddress();
