import { DEEP_COIN_TYPE, SUI_COIN_TYPE } from "./constants";

/**
 * Converts a human-readable percentage into the raw format expected by the contract.
 * The contract expects 1_000_000_000 to represent 100%.
 * @param percent The percentage value (e.g., 0.2 for 0.2%, 100 for 100%)
 */
export function percentToRaw(percent: number): number {
  // Use Math.round to avoid dangerous floating point truncation (e.g. 0.2 * 10_000_000 = 1999999.999...)
  const raw = Math.round(percent * 10_000_000);

  // The contract strictly enforces FEE_PRECISION_MULTIPLE = 1000
  if (raw % 1000 !== 0) {
    throw new Error(
      `Invalid precision for percentage ${percent}%. The contract requires fees ` +
        `to be a multiple of 0.0001% (0.01 bps). Generated raw value: ${raw}`,
    );
  }

  // Contract absolute max is 100% (1_000_000_000)
  if (raw < 0 || raw > 1_000_000_000) {
    throw new Error(`Percentage ${percent}% is out of valid bounds (0% to 100%).`);
  }

  return raw;
}

// ---------------------------------------------------------
// Pool Default Fees
// ---------------------------------------------------------
export const defaultFeesConfig = {
  deepFeeTypeTakerRate: percentToRaw(0.06), // 6 bps = 600_000 raw
  deepFeeTypeMakerRate: percentToRaw(0.03), // 3 bps = 300_000 raw
  inputCoinFeeTypeTakerRate: percentToRaw(0.05), // 5 bps = 500_000 raw
  inputCoinFeeTypeMakerRate: percentToRaw(0.02), // 2 bps = 200_000 raw
  maxDeepFeeCoverageDiscountRate: percentToRaw(25), // 25% = 250_000_000 raw
};

// ---------------------------------------------------------
// Pool-Specific Fees
// ---------------------------------------------------------
export const poolSpecificFeesConfig = [
  {
    // DEEP_SUI pool id
    poolId: "0xb663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22",
    baseCoin: DEEP_COIN_TYPE,
    quoteCoin: SUI_COIN_TYPE,
    fees: {
      deepFeeTypeTakerRate: percentToRaw(0.06),
      deepFeeTypeMakerRate: percentToRaw(0.03),
      inputCoinFeeTypeTakerRate: percentToRaw(0.05),
      inputCoinFeeTypeMakerRate: percentToRaw(0.02),
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  // Add more pools here as needed...
];
