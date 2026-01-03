import { Transaction } from "@mysten/sui/transactions";
import { destinationAddress, keypair, provider, user } from "../common";
import { SUI_COIN_TYPE } from "../constants";

// Maximum objects per transaction (conservative limit)
const MAX_OBJECTS_PER_PTB = 1500;

interface CoinGroup {
  coinType: string;
  objectIds: string[];
}

// Helper function to format balance with decimals
function formatBalance(
  balance: string | number | bigint,
  decimals: number = 9
): string {
  const balanceBigInt = BigInt(balance);
  const amount = Number(balanceBigInt) / 10 ** decimals;
  return amount.toFixed(decimals).replace(/\.?0+$/, "");
}

// yarn ts-node examples/wrapper/send-coins-batch-to-destination.ts > logs/send-coins-batch.log 2>&1
(async () => {
  console.log(`\n========== SEND ALL COINS TO DESTINATION ==========`);
  console.log(`From address: ${user}`);
  console.log(`To address: ${destinationAddress || "(NOT SET)"}\n`);

  // Safety checks
  if (!destinationAddress) {
    console.error(`❌ ERROR: DESTINATION_ADDRESS is not set!`);
    console.error(
      `Please edit the script and set DESTINATION_ADDRESS before running.\n`
    );
    process.exit(1);
  }

  if (destinationAddress === user) {
    console.error(
      `❌ ERROR: Destination address is the same as sender address!`
    );
    console.error(`This would be pointless. Please set a different address.\n`);
    process.exit(1);
  }

  // Get initial SUI balance
  const initialSuiBalance = await provider.getBalance({
    owner: user,
    coinType: SUI_COIN_TYPE,
  });
  console.log(
    `Initial SUI balance: ${formatBalance(initialSuiBalance.totalBalance)} SUI`
  );
  console.log(
    `Initial SUI coin objects: ${initialSuiBalance.coinObjectCount}\n`
  );

  // Fetch all coins for the user
  console.log(`Fetching all coins from sender...`);

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

  // Separate SUI coins from other coins (SUI will be sent LAST)
  let suiCoins: string[] = [];
  const nonSuiCoins: CoinGroup[] = [];

  for (const [coinType, objectIds] of coinGroups.entries()) {
    // Check if this is SUI (handles both 0x2::sui::SUI and full address formats)
    const isSuiCoin =
      coinType === SUI_COIN_TYPE ||
      coinType.endsWith("::sui::SUI") ||
      coinType === "0x2::sui::SUI";

    if (!isSuiCoin) {
      nonSuiCoins.push({ coinType, objectIds });
    } else {
      // Collect all SUI coins
      suiCoins = objectIds;
    }
  }

  // Display all coins to be sent
  console.log(`========== COINS TO SEND ==========`);
  console.log(`Non-SUI coins: ${nonSuiCoins.length} types`);
  for (const { coinType, objectIds } of nonSuiCoins) {
    const coinSymbol = coinType.split("::").pop() || "UNKNOWN";
    console.log(`  ${coinSymbol}: ${objectIds.length} objects`);
  }
  console.log(`\nSUI coins: ${suiCoins.length} objects (will be sent LAST)`);
  console.log(``);

  if (nonSuiCoins.length === 0 && suiCoins.length === 0) {
    console.log(`No coins found to send. Exiting.`);
    return;
  }

  // Confirm before proceeding
  console.log(`⚠️  WARNING: This will send ALL coins to ${destinationAddress}`);
  console.log(`Starting transfer in 3 seconds...\n`);
  await new Promise((resolve) => setTimeout(resolve, 3000));

  console.log(`========== BUILDING TRANSFER PTBs ==========\n`);

  // ========== STEP 1: Build PTBs for non-SUI coins ==========
  const ptbs: { tx: Transaction; description: string }[] = [];

  if (nonSuiCoins.length > 0) {
    console.log(`Building PTBs for non-SUI coins...`);

    let currentTx = new Transaction();
    let currentObjectCount = 0;
    let coinsInCurrentBatch = 0;
    let ptbNumber = 0;

    for (const { coinType, objectIds } of nonSuiCoins) {
      const coinSymbol = coinType.split("::").pop() || "UNKNOWN";

      // Check if adding this coin type would exceed limit
      if (
        currentObjectCount + objectIds.length > MAX_OBJECTS_PER_PTB &&
        coinsInCurrentBatch > 0
      ) {
        // Save current PTB and start a new one
        ptbNumber++;
        ptbs.push({
          tx: currentTx,
          description: `Non-SUI PTB #${ptbNumber} (${coinsInCurrentBatch} types, ${currentObjectCount} objects)`,
        });
        console.log(
          `  Built PTB #${ptbNumber}: ${coinsInCurrentBatch} coin types, ${currentObjectCount} objects`
        );

        currentTx = new Transaction();
        currentObjectCount = 0;
        coinsInCurrentBatch = 0;
      }

      // Add all objects of this coin type to current PTB
      currentTx.transferObjects(
        objectIds.map((id) => currentTx.object(id)),
        currentTx.pure.address(destinationAddress)
      );

      currentObjectCount += objectIds.length;
      coinsInCurrentBatch++;
    }

    // Don't forget the last PTB
    if (coinsInCurrentBatch > 0) {
      ptbNumber++;
      ptbs.push({
        tx: currentTx,
        description: `Non-SUI PTB #${ptbNumber} (${coinsInCurrentBatch} types, ${currentObjectCount} objects)`,
      });
      console.log(
        `  Built PTB #${ptbNumber}: ${coinsInCurrentBatch} coin types, ${currentObjectCount} objects`
      );
    }

    console.log(`\nBuilt ${ptbs.length} PTB(s) for non-SUI coins\n`);
  }

  // ========== STEP 2: Execute non-SUI PTBs sequentially ==========
  if (ptbs.length > 0) {
    console.log(`========== EXECUTING NON-SUI TRANSFERS ==========\n`);

    let successfulBatches = 0;
    let failedBatches = 0;

    for (let i = 0; i < ptbs.length; i++) {
      const { tx, description } = ptbs[i];
      console.log(`Executing ${description}...`);

      try {
        const res = await provider.signAndExecuteTransaction({
          transaction: tx,
          signer: keypair,
          options: {
            showEffects: true,
          },
        });

        // Check if transaction actually succeeded on-chain
        if (res.effects?.status?.status === "success") {
          console.log(`  ✓ Success! Digest: ${res.digest}\n`);
          successfulBatches++;
        } else {
          console.error(`  ✗ Failed on-chain! Digest: ${res.digest}`);
          console.error(`    Status: ${res.effects?.status?.status}`);
          console.error(
            `    Error: ${res.effects?.status?.error || "Unknown error"}\n`
          );
          failedBatches++;
        }
      } catch (error) {
        console.error(`  ✗ Failed to submit:`);
        console.error(
          `    Error: ${error instanceof Error ? error.message : String(error)}\n`
        );
        failedBatches++;
      }
    }

    console.log(
      `Non-SUI transfers: ${successfulBatches} successful, ${failedBatches} failed\n`
    );
  }

  // ========== STEP 3: Send SUI coins LAST (with dynamic gas calculation) ==========
  if (suiCoins.length > 0) {
    console.log(`========== SENDING SUI (LAST) ==========\n`);

    // Wait for network to settle after previous transactions
    console.log(`Waiting 5 seconds for balance to update...`);
    await new Promise((resolve) => setTimeout(resolve, 5000));
    console.log(`Continuing...\n`);

    try {
      // Calculate available SUI to send based on actual gas costs

      // Double-check balance before sending
      const currentBalance = await provider.getBalance({
        owner: user,
        coinType: SUI_COIN_TYPE,
      });

      console.log(
        `Balance right now: ${formatBalance(currentBalance.totalBalance)} SUI`
      );

      if (BigInt(currentBalance.totalBalance) <= 0n) {
        console.log(
          `Not enough SUI to send after reserving for gas. Skipping.\n`
        );
      } else {
        const tx = new Transaction();

        tx.transferObjects([tx.gas], tx.pure.address(destinationAddress));

        const res = await provider.signAndExecuteTransaction({
          transaction: tx,
          signer: keypair,
          options: {
            showEffects: true,
          },
        });

        // Check if transaction actually succeeded on-chain
        if (res.effects?.status?.status === "success") {
          console.log(`✓ SUI transfer successful! Digest: ${res.digest}`);
          console.log(
            `  Sent: ${formatBalance(currentBalance.totalBalance)} SUI\n`
          );
        } else {
          console.error(
            `✗ SUI transfer failed on-chain! Digest: ${res.digest}`
          );
          console.error(`  Status: ${res.effects?.status?.status}`);
          console.error(
            `  Error: ${res.effects?.status?.error || "Unknown error"}\n`
          );
        }
      }
    } catch (error) {
      console.error(`✗ SUI transfer failed:`);
      console.error(
        `  Error: ${error instanceof Error ? error.message : String(error)}\n`
      );
    }
  }

  // Final summary
  console.log(`\n========== TRANSFER COMPLETE ==========`);

  try {
    const finalSuiBalance = await provider.getBalance({
      owner: user,
      coinType: SUI_COIN_TYPE,
    });

    console.log(
      `Final SUI balance: ${formatBalance(finalSuiBalance.totalBalance)} SUI`
    );
    console.log(`Final SUI coin objects: ${finalSuiBalance.coinObjectCount}`);

    const gasSpent =
      BigInt(initialSuiBalance.totalBalance) -
      BigInt(finalSuiBalance.totalBalance);
    console.log(
      `Total gas spent: ${formatBalance(gasSpent)} SUI (${gasSpent} MIST)`
    );
  } catch (error) {
    console.error(`Failed to fetch final balance: ${error}`);
  }

  console.log(`\n========================================\n`);
})();
