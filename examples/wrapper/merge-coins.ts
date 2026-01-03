import { Transaction } from "@mysten/sui/transactions";
import { keypair, provider, user } from "../common";
import { SUI_COIN_TYPE } from "../constants";

// Maximum coins to merge per transaction (Sui protocol limit ~2048 objects,
// we use 512 to stay well within limits)
const MAX_COINS_PER_TX = 511;

// Delay in milliseconds between batches that touch the same destination coin
// This prevents "object not available for consumption" errors due to version conflicts
const BATCH_DELAY_MS = 5000; // 5 seconds

interface CoinGroup {
  coinType: string;
  objectIds: string[];
}

// Helper function to format SUI balance with decimals
function formatSuiBalance(balance: string | number | bigint): string {
  const balanceBigInt = BigInt(balance);
  const suiAmount = Number(balanceBigInt) / 10 ** 9;
  return suiAmount.toFixed(9).replace(/\.?0+$/, ""); // Remove trailing zeros
}

// Helper function to sleep/delay
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// yarn ts-node examples/wrapper/merge-coins.ts > logs/merge-coins.log 2>&1
(async () => {
  console.log(`\n========== COIN MERGE SCRIPT ==========`);
  console.log(`User address: ${user}\n`);

  // Step 4: Get initial SUI balance
  const initialSuiBalance = await provider.getBalance({
    owner: user,
    coinType: SUI_COIN_TYPE,
  });
  console.log(
    `Initial SUI balance: ${formatSuiBalance(initialSuiBalance.totalBalance)} SUI`
  );
  console.log(
    `Initial SUI coin objects count: ${initialSuiBalance.coinObjectCount}\n`
  );

  // Step 1: Get all coin objects for the user
  console.log(`Fetching all coins for user...`);

  const coinGroups: Map<string, string[]> = new Map();
  let cursor: string | null | undefined = null;
  let hasNextPage = true;

  while (hasNextPage) {
    const response = await provider.getAllCoins({
      owner: user,
      cursor,
    });

    for (const coin of response.data) {
      const existing = coinGroups.get(coin.coinType) || [];
      existing.push(coin.coinObjectId);
      coinGroups.set(coin.coinType, existing);
    }

    cursor = response.nextCursor;
    hasNextPage = response.hasNextPage;
  }

  console.log(`Found ${coinGroups.size} unique coin types.\n`);

  // Step 2 & 3: Find coins with more than 1 object and print them
  const coinsToMerge: CoinGroup[] = [];

  console.debug("coinGroups: ", coinGroups);

  console.log(`========== COINS WITH MULTIPLE OBJECTS ==========`);
  for (const [coinType, objectIds] of coinGroups.entries()) {
    if (objectIds.length > 1) {
      const coinSymbol = coinType.split("::").pop() || "UNKNOWN";
      console.log(`Coin: ${coinSymbol}`);
      console.log(`  Type: ${coinType}`);
      console.log(`  Objects count: ${objectIds.length}`);
      console.log(``);

      coinsToMerge.push({ coinType, objectIds });
    }
  }

  if (coinsToMerge.length === 0) {
    console.log(`No coins with multiple objects found. Nothing to merge.`);
    return;
  }

  console.log(`\n========== STARTING MERGE PROCESS ==========\n`);

  // Step 5 & 6: Prepare and execute merge transactions
  for (const { coinType, objectIds } of coinsToMerge) {
    const coinSymbol = coinType.split("::").pop() || "UNKNOWN";
    const isSui = coinType === SUI_COIN_TYPE;

    console.log(`Processing ${coinSymbol} (${objectIds.length} objects)...`);

    // Split into batches of MAX_COINS_PER_TX
    // For merging, we need at least 2 coins (1 destination + 1 source)
    let objectsToMerge = [...objectIds];
    let batchNumber = 0;

    while (objectsToMerge.length > 1) {
      batchNumber++;
      const tx = new Transaction();

      if (isSui) {
        // For SUI coins, merge to gas coin
        // Take up to MAX_COINS_PER_TX coins to merge (excluding gas coin)
        const coinsToMergeThisBatch = objectsToMerge.slice(0, MAX_COINS_PER_TX);

        if (coinsToMergeThisBatch.length === 0) break;

        console.log(
          `  Batch ${batchNumber}: Merging ${coinsToMergeThisBatch.length} SUI coins to gas coin...`
        );

        tx.mergeCoins(
          tx.gas,
          coinsToMergeThisBatch.map((id) => tx.object(id))
        );

        // Remove merged coins from the list
        objectsToMerge = objectsToMerge.slice(coinsToMergeThisBatch.length);
      } else {
        // For non-SUI coins, merge to the first coin
        const destinationCoin = objectsToMerge[0];
        const sourcesThisBatch = objectsToMerge.slice(1, MAX_COINS_PER_TX + 1);

        if (sourcesThisBatch.length === 0) break;

        console.log(
          `  Batch ${batchNumber}: Merging ${sourcesThisBatch.length} ${coinSymbol} coins to first coin...`
        );

        tx.mergeCoins(
          tx.object(destinationCoin),
          sourcesThisBatch.map((id) => tx.object(id))
        );

        // Keep destination, remove merged sources
        objectsToMerge = [
          destinationCoin,
          ...objectsToMerge.slice(MAX_COINS_PER_TX + 1),
        ];
      }

      // Step 7: Execute and log response
      try {
        const res = await provider.signAndExecuteTransaction({
          transaction: tx,
          signer: keypair,
        });

        console.log(`  ✓ Success! Digest: ${res.digest}`);

        // Add delay for non-SUI coins before next batch to prevent version conflicts
        // SUI coins don't need delay as they merge to gas coin (different each time)
        if (!isSui && objectsToMerge.length > 1) {
          console.log(
            `  ⏳ Waiting ${BATCH_DELAY_MS / 1000}s before next batch...`
          );
          await sleep(BATCH_DELAY_MS);
        }
      } catch (error) {
        console.error(
          `  ✗ Failed to merge ${coinSymbol} batch ${batchNumber}:`
        );
        console.error(
          `    Error: ${error instanceof Error ? error.message : String(error)}`
        );

        // Also add delay after errors to let the network state settle
        if (!isSui && objectsToMerge.length > 1) {
          console.log(`  ⏳ Waiting ${BATCH_DELAY_MS / 1000}s after error...`);
          await sleep(BATCH_DELAY_MS);
        }
      }
    }

    console.log(`  Completed merging ${coinSymbol}\n`);
  }

  // Step 8: Print new SUI balance
  console.log(`\n========== FINAL RESULTS ==========`);

  try {
    const finalSuiBalance = await provider.getBalance({
      owner: user,
      coinType: SUI_COIN_TYPE,
    });

    console.log(
      `Final SUI balance: ${formatSuiBalance(finalSuiBalance.totalBalance)} SUI`
    );
    console.log(
      `Final SUI coin objects count: ${finalSuiBalance.coinObjectCount}`
    );

    const balanceDiff =
      BigInt(initialSuiBalance.totalBalance) -
      BigInt(finalSuiBalance.totalBalance);
    console.log(
      `Gas spent: ${formatSuiBalance(balanceDiff)} SUI (${balanceDiff} MIST)`
    );
  } catch (error) {
    console.error(`Failed to fetch final balance:`);
    console.error(
      `  Error: ${error instanceof Error ? error.message : String(error)}`
    );
  }

  console.log(`\n========== MERGE COMPLETE ==========\n`);
})();
