import { DEEP_COIN_TYPE, SUI_COIN_TYPE, USDC_COIN_TYPE, WAL_COIN_TYPE } from "./constants";

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
  deepFeeTypeMakerRate: percentToRaw(0.04), // 3 bps = 300_000 raw
  inputCoinFeeTypeTakerRate: percentToRaw(0.05), // 5 bps = 500_000 raw
  inputCoinFeeTypeMakerRate: percentToRaw(0.03), // 2 bps = 200_000 raw
  maxDeepFeeCoverageDiscountRate: percentToRaw(25), // 25% = 250_000_000 raw
};

// ---------------------------------------------------------
// Pool-Specific Fees
// ---------------------------------------------------------
export const poolSpecificFeesConfig = [
  {
    // DEEP_USDC
    poolId: "0xde096bb2c59538a25c89229127fe0bc8b63ecdbe52a3693099cc40a1d8a2cfd4",
    baseCoin: DEEP_COIN_TYPE,
    quoteCoin: USDC_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.1),
      inputCoinFeeTypeTakerRate: percentToRaw(0.1),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  {
    // DEEP_SUI
    poolId: "0xb663828d6217467c8a1838a03793da896cbe745b150ebd57d82f814ca579fc22",
    baseCoin: DEEP_COIN_TYPE,
    quoteCoin: SUI_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.1),
      inputCoinFeeTypeTakerRate: percentToRaw(0.1),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  {
    // SUI_USDC
    poolId: "0xe05dafb5133bcffb8d59f4e12465dc0e9faeaa05e3e342a08fe135800e3e4407",
    baseCoin: SUI_COIN_TYPE,
    quoteCoin: USDC_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.1),
      inputCoinFeeTypeTakerRate: percentToRaw(0.09),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  {
    // WAL_USDC
    poolId: "0x56a1c985c1f1123181d6b881714793689321ba24301b3585eec427436eb1c76d",
    baseCoin: WAL_COIN_TYPE,
    quoteCoin: USDC_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.08),
      inputCoinFeeTypeTakerRate: percentToRaw(0.075),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  {
    // XBTC_USDC
    poolId: "0x20b9a3ec7a02d4f344aa1ebc5774b7b0ccafa9a5d76230662fdc0300bb215307",
    baseCoin: "0x876a4b7bce8aeaef60464c11f4026903e9afacab79b9b142686158aa86560b50::xbtc::XBTC",
    quoteCoin: USDC_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.08),
      inputCoinFeeTypeTakerRate: percentToRaw(0.075),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  {
    // WBTC_USDC
    poolId: "0xf5142aafa24866107df628bf92d0358c7da6acc46c2f10951690fd2b8570f117",
    baseCoin: "0x0041f9f9344cac094454cd574e333c4fdb132d7bcc9379bcd4aab485b2a63942::wbtc::WBTC",
    quoteCoin: USDC_COIN_TYPE,
    fees: {
      // Maker fees
      deepFeeTypeMakerRate: percentToRaw(0.06),
      inputCoinFeeTypeMakerRate: percentToRaw(0.06),
      // Taker fees
      deepFeeTypeTakerRate: percentToRaw(0.08),
      inputCoinFeeTypeTakerRate: percentToRaw(0.075),
      // Discount
      maxDeepFeeCoverageDiscountRate: percentToRaw(25),
    },
  },
  // Add more pools here as needed...
];
