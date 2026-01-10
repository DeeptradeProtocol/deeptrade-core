import { Transaction } from "@mysten/sui/transactions";
import { destinationAddress, keypair, provider, user } from "../common";

/**
 * Script to send a specific list of object IDs to the destination address.
 *
 * Usage:
 * 1. Edit the OBJECT_IDS_TO_SEND array below.
 * 2. Ensure DESTINATION_ADDRESS is set in your .env file.
 * 3. Run: yarn ts-node examples/wrapper/send-objects-batch-to-destination.ts
 */

// --- SPECIFY YOUR OBJECT IDS HERE ---
const OBJECT_IDS_TO_SEND: string[] = [];
// ------------------------------------

(async () => {
  console.log(`\n========== SEND OBJECTS TO DESTINATION ==========`);
  console.log(`From address: ${user}`);
  console.log(`To address:   ${destinationAddress || "(NOT SET)"}\n`);

  // Safety checks
  if (!destinationAddress) {
    console.error(`❌ ERROR: DESTINATION_ADDRESS is not set in .env!`);
    process.exit(1);
  }

  if (destinationAddress === user) {
    console.error(
      `❌ ERROR: Destination address is the same as sender address!`
    );
    process.exit(1);
  }

  const ids = OBJECT_IDS_TO_SEND.filter((id) => id.startsWith("0x"));

  if (ids.length === 0) {
    console.error(
      `❌ ERROR: No valid object IDs specified in OBJECT_IDS_TO_SEND array.`
    );
    process.exit(1);
  }

  console.log(`Objects to send (${ids.length}):`);
  ids.forEach((id) => console.log(`  - ${id}`));

  // Confirm before proceeding
  console.log(
    `\n⚠️  WARNING: This will transfer ${ids.length} objects to ${destinationAddress}`
  );
  console.log(`Starting transfer in 3 seconds...\n`);
  await new Promise((resolve) => setTimeout(resolve, 3000));

  try {
    const tx = new Transaction();

    // Add all specified objects to the transfer
    tx.transferObjects(
      ids.map((id) => tx.object(id)),
      tx.pure.address(destinationAddress)
    );

    console.log(`Executing transaction...`);
    const res = await provider.signAndExecuteTransaction({
      transaction: tx,
      signer: keypair,
      options: {
        showEffects: true,
      },
    });

    if (res.effects?.status?.status === "success") {
      console.log(`✅ Success!`);
      console.log(`Transaction Digest: ${res.digest}`);
    } else {
      console.error(`❌ Transaction failed on-chain!`);
      console.error(`Status: ${res.effects?.status?.status}`);
      console.error(`Error: ${res.effects?.status?.error || "Unknown error"}`);
      console.log(`Digest: ${res.digest}`);
    }
  } catch (error) {
    console.error(`❌ Failed to execute transfer:`);
    console.error(error instanceof Error ? error.message : String(error));
  }

  console.log(`\n================================================\n`);
})();
