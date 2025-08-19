// examples/multisig/test-multisig-tx.ts
import { exec } from "child_process";
import { promisify } from "util";
import { MULTISIG_CONFIG } from "./multisig";

const execAsync = promisify(exec);

/**
 * Executes a shell command and returns its output
 */
async function executeCommand(command: string): Promise<string> {
  try {
    console.log("\nExecuting command:");
    console.log(command);
    console.log("\nOutput:");

    const { stdout, stderr } = await execAsync(command);
    if (stderr) {
      console.error("Command stderr:", stderr);
    }
    console.log(stdout);
    return stdout.trim();
  } catch (error) {
    console.error("Error executing command:", error);
    throw error;
  }
}

/**
 * Processes a base64 transaction through Sui multisig flow
 */
async function processSuiMultisigTransaction(txBytes: string): Promise<void> {
  console.log("\n=== Starting Multisig Transaction Process ===\n");

  // Get signers from config
  const publicKeys = MULTISIG_CONFIG.publicKeys;
  const weights = MULTISIG_CONFIG.weights;
  const threshold = MULTISIG_CONFIG.threshold;

  // Collect signatures
  const signatures: string[] = [];
  for (let i = 0; i < publicKeys.length; i++) {
    console.log(`${i + 1}. Signing with ${publicKeys[i].toSuiAddress()}...`);
    const sigResult = await executeCommand(
      `sui keytool sign --address ${publicKeys[i].toSuiAddress()} --data ${txBytes}`,
    );
    const signature = extractSignature(sigResult);
    signatures.push(signature);
    console.log(`✓ Signature obtained:`, signature, "\n");
  }

  console.log("Combining signatures...");
  const pksFormatted = publicKeys.map((pk) => pk.toSuiPublicKey()).join(" ");

  const weightsFormatted = weights.join(" ");
  const combineResult = await executeCommand(
    `sui keytool multi-sig-combine-partial-sig \
        --pks ${pksFormatted} \
        --weights ${weightsFormatted} \
        --threshold ${threshold} \
        --sigs ${signatures.join(" ")}`,
  );
  const combinedSignature = extractCombinedSignature(combineResult);
  console.log("✓ Signatures combined:", combinedSignature, "\n");

  console.log("4. Executing final transaction...");
  const finalCommand = `sui client execute-signed-tx \
--tx-bytes ${txBytes} \
--signatures ${combinedSignature}`;

  const executionResult = await executeCommand(finalCommand);
  console.log("\n=== Transaction Process Complete ===\n");

  // Print summary
  console.log("Transaction Summary:");
  console.log("-------------------");
  console.log("Individual Signatures:", signatures);
  console.log("Combined Signature:", combinedSignature);
  console.log("Final Result:", executionResult);
}

/**
 * Extract signature from keytool sign output
 */
function extractSignature(output: string): string {
  const match = output.match(/suiSignature │ (.+?) │/);
  return match ? match[1].trim() : "";
}

/**
 * Extract combined signature from multi-sig-combine output
 */
function extractCombinedSignature(output: string): string {
  const match = output.match(/multisigParsed\s*│\s*([^\s│]+)\s*│/);
  return match ? match[1].trim() : "";
}

// Main execution
async function main() {
  const txBytes = process.argv[2];

  if (!txBytes) {
    console.error("Error: Transaction bytes (base64) required");
    console.error("Usage: ts-node test-multisig-tx.ts <transaction-bytes>");
    process.exit(1);
  }

  try {
    await processSuiMultisigTransaction(txBytes);
  } catch (error) {
    console.error("\nError processing transaction:", error);
    process.exit(1);
  }
}

main();
