#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

class MoveCodeAnalyzer {
  constructor(options = {}) {
    this.options = {
      skipBlankLines: true,
      skipComments: true,
      showDetails: false,
      skipDeprecated: true, // Skip deprecated by default
      skipTestFunctions: true, // Skip test functions by default
      ...options,
    };

    // Extensible patterns for future features
    this.patterns = {
      singleLineComment: /^\s*\/\/.*$/,
      multiLineCommentStart: /^\s*\/\*.*$/,
      multiLineCommentEnd: /.*\*\/\s*$/,
      multiLineCommentFull: /^\s*\/\*.*\*\/\s*$/,
      docComment: /^\s*\/\/\/.*$/,
      blankLine: /^\s*$/,
      // Deprecated method patterns (based on actual codebase)
      deprecatedAttribute: /^\s*#\[\s*$/, // More precise: must start with #[
      deprecatedSectionHeader: /^\s*\/\/.*===.*deprecated.*===/i,
      deprecatedComment: /^\s*\/\/.*deprecated/i,
      deprecatedConstant: /^\s*const\s+.*deprecated.*:/i,
      deprecatedAbort: /^\s*abort\s+.*deprecated/i,
      // Generic patterns
      todoRemove: /\/\/.*TODO.*REMOVE/i,
      legacyCode: /\/\/.*LEGACY/i,
      // Test function patterns
      testSectionHeader: /^\s*\/\/.*===.*test.*===/i,
    };
  }

  isDeprecatedLine(line) {
    return (
      this.patterns.deprecatedAttribute.test(line) ||
      this.patterns.deprecatedSectionHeader.test(line) ||
      this.patterns.deprecatedComment.test(line) ||
      this.patterns.deprecatedConstant.test(line) ||
      this.patterns.deprecatedAbort.test(line) ||
      this.patterns.todoRemove.test(line) ||
      this.patterns.legacyCode.test(line)
    );
  }

  isTestFunctionLine(line) {
    return this.patterns.testSectionHeader.test(line);
  }

  isDeprecatedAttribute(line) {
    return this.patterns.deprecatedAttribute.test(line);
  }

  isFunctionStart(line) {
    return /^\s*public\s+fun\s+|^\s*fun\s+/.test(line);
  }

  countBraces(line) {
    // Remove string literals and comments before counting braces
    let cleanLine = line;

    // Remove string literals (basic implementation for b"..." and "...")
    cleanLine = cleanLine.replace(/b?"[^"]*"/g, '""');

    // Remove single-line comments
    cleanLine = cleanLine.replace(/\/\/.*$/, "");

    const openBraces = (cleanLine.match(/{/g) || []).length;
    const closeBraces = (cleanLine.match(/}/g) || []).length;
    return openBraces - closeBraces;
  }

  startsAttribute(line) {
    return /^\s*#\[/.test(line);
  }

  containsDeprecated(line) {
    // Match 'deprecated(' anywhere on the line within attribute context
    return /deprecated\s*\(/.test(line.trim());
  }

  startsFunctionBody(line) {
    return line.includes("{");
  }

  analyzeFile(filePath) {
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split("\n");

    const stats = {
      total: lines.length,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0,
      testFunctions: 0,
    };

    let inMultiLineComment = false;
    let inDeprecatedSection = false;
    let inTestSection = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      // Handle multi-line comments
      if (
        this.patterns.multiLineCommentStart.test(line) &&
        !this.patterns.multiLineCommentFull.test(line)
      ) {
        inMultiLineComment = true;
        stats.comments++;
        continue;
      }

      if (inMultiLineComment) {
        stats.comments++;
        if (this.patterns.multiLineCommentEnd.test(line)) {
          inMultiLineComment = false;
        }
        continue;
      }

      // Test section detection - start counting after the marker
      if (this.patterns.testSectionHeader.test(line)) {
        inTestSection = true;
        stats.comments++; // Count the marker itself as a comment
        continue;
      }

      // Simple deprecated section detection - start counting after the marker
      if (line.includes("// === Deprecated Functions ===")) {
        inDeprecatedSection = true;
        stats.comments++; // Count the marker itself as a comment
        continue;
      }

      // Line classification with proper prioritization
      if (this.patterns.blankLine.test(line)) {
        stats.blank++;
      } else if (
        this.patterns.docComment.test(line) ||
        this.patterns.singleLineComment.test(line) ||
        this.patterns.multiLineCommentFull.test(line)
      ) {
        stats.comments++;
      } else if (inDeprecatedSection) {
        // Inside deprecated section - count as deprecated code (including attributes, function signatures, bodies)
        stats.deprecated++;
      } else if (inTestSection) {
        // Inside test section - count as test functions
        stats.testFunctions++;
      } else {
        stats.code++;
      }
    }

    return stats;
  }

  analyzeDirectory(dirPath) {
    const results = {};
    const files = fs.readdirSync(dirPath);

    const moveFiles = files.filter((file) => file.endsWith(".move"));

    let totals = {
      total: 0,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0,
      testFunctions: 0,
    };

    moveFiles.forEach((file) => {
      const filePath = path.join(dirPath, file);
      const stats = this.analyzeFile(filePath);
      results[file] = stats;

      // Add to totals
      Object.keys(totals).forEach((key) => {
        totals[key] += stats[key];
      });
    });

    return { files: results, totals };
  }

  analyzeTestDirectory(dirPath) {
    const results = {};

    let totals = {
      total: 0,
      code: 0,
      comments: 0,
      blank: 0,
      deprecated: 0,
      testFunctions: 0, // Should be 0 for tests but keeping for consistency
    };

    // Recursively analyze test subdirectories
    const analyzeSubdir = (subDirPath, prefix = "") => {
      if (!fs.existsSync(subDirPath)) return;

      const items = fs.readdirSync(subDirPath);

      items.forEach((item) => {
        const itemPath = path.join(subDirPath, item);
        const stat = fs.statSync(itemPath);

        if (stat.isDirectory()) {
          // Recursively analyze subdirectories
          analyzeSubdir(itemPath, prefix + item + "/");
        } else if (item.endsWith(".move")) {
          // Analyze test file
          const stats = this.analyzeFile(itemPath);
          const key = prefix + item;
          results[key] = stats;

          // Add to totals
          Object.keys(totals).forEach((statKey) => {
            totals[statKey] += stats[statKey];
          });
        }
      });
    };

    analyzeSubdir(dirPath);
    return { files: results, totals };
  }

  getEffectiveLines(stats) {
    let effective = stats.total;

    if (this.options.skipBlankLines) {
      effective -= stats.blank;
    }

    if (this.options.skipComments) {
      effective -= stats.comments;
    }

    if (this.options.skipDeprecated) {
      effective -= stats.deprecated;
    }

    if (this.options.skipTestFunctions) {
      effective -= stats.testFunctions;
    }

    return Math.max(0, effective);
  }

  formatResults(sourcesAnalysis, testsAnalysis = null) {
    console.log("\n📊 Sui Deeptrade Package - Lines of Code Analysis");
    console.log("=".repeat(67));

    // Sources section
    this.formatSection("📁 Sources Analysis", sourcesAnalysis, true);

    // Tests section (if available)
    if (testsAnalysis && Object.keys(testsAnalysis.files).length > 0) {
      this.formatSection("🧪 Tests Analysis", testsAnalysis, false);
    }

    // Overall summary
    console.log("\n📊 Overall Summary:");
    const sourcesEffective = this.getEffectiveLines(sourcesAnalysis.totals);
    console.log(`🎯 Effective LoC (sources only): ${sourcesEffective} lines`);

    if (testsAnalysis && Object.keys(testsAnalysis.files).length > 0) {
      const testsEffective = this.getEffectiveLines(testsAnalysis.totals);
      console.log(`🧪 Test LoC: ${testsEffective} lines`);
      console.log(
        `📈 Total project lines: ${
          sourcesAnalysis.totals.total + testsAnalysis.totals.total
        } lines`
      );
    }

    if (sourcesAnalysis.totals.deprecated > 0) {
      console.log(
        `🔄 Note: ${sourcesAnalysis.totals.deprecated} deprecated method lines detected and excluded from effective count`
      );
    }

    if (sourcesAnalysis.totals.testFunctions > 0) {
      if (this.options.skipTestFunctions) {
        console.log(
          `🧪 Note: ${sourcesAnalysis.totals.testFunctions} test function lines detected and excluded from effective count`
        );
      } else {
        console.log(
          `🧪 Note: ${sourcesAnalysis.totals.testFunctions} test function lines detected and included in effective count`
        );
      }
    }

    if (this.options.showDetails) {
      console.log("\n📋 Configuration:");
      console.log(`• Skip blank lines: ${this.options.skipBlankLines}`);
      console.log(`• Skip comments: ${this.options.skipComments}`);
      console.log(`• Skip deprecated: ${this.options.skipDeprecated}`);
      console.log(`• Skip test functions: ${this.options.skipTestFunctions}`);
    }
  }

  formatSection(title, analysis, showDeprecated) {
    console.log(`\n${title}:`);

    // Determine if we need wider columns for test files
    const isTestSection = title.includes("Tests");
    const moduleWidth = isTestSection ? 35 : 20;
    // Calculate total width based on columns: Module + Total + Code + Comments + Blank + (Deprecated + Test if showDeprecated)
    const baseWidth = moduleWidth + 8 + 8 + 10 + 8; // Module + Total + Code + Comments + Blank
    const totalWidth = showDeprecated ? baseWidth + 12 + 8 : baseWidth; // Add Deprecated + Test columns

    console.log("-".repeat(totalWidth));

    const headers =
      "Module".padEnd(moduleWidth) +
      "Total".padEnd(8) +
      "Code".padEnd(8) +
      "Comments".padEnd(10) +
      "Blank".padEnd(8);
    if (showDeprecated) {
      console.log(headers + "Deprecated".padEnd(12) + "Test".padEnd(8));
    } else {
      console.log(headers);
    }
    console.log("-".repeat(totalWidth));

    // Sort files by code lines (descending)
    const sortedFiles = Object.entries(analysis.files).sort(
      ([, a], [, b]) => b.code - a.code
    );

    sortedFiles.forEach(([file, stats]) => {
      let filename = file.replace(".move", "");

      // Truncate filename if it's too long for the column
      if (filename.length > moduleWidth - 1) {
        filename = filename.substring(0, moduleWidth - 4) + "...";
      }

      let row =
        filename.padEnd(moduleWidth) +
        stats.total.toString().padEnd(8) +
        stats.code.toString().padEnd(8) +
        stats.comments.toString().padEnd(10) +
        stats.blank.toString().padEnd(8);

      if (showDeprecated) {
        row +=
          stats.deprecated.toString().padEnd(12) +
          stats.testFunctions.toString().padEnd(8);
      }
      console.log(row);
    });

    // Section totals
    console.log("-".repeat(totalWidth));
    let totalRow =
      "TOTAL".padEnd(moduleWidth) +
      analysis.totals.total.toString().padEnd(8) +
      analysis.totals.code.toString().padEnd(8) +
      analysis.totals.comments.toString().padEnd(10) +
      analysis.totals.blank.toString().padEnd(8);

    if (showDeprecated) {
      totalRow +=
        analysis.totals.deprecated.toString().padEnd(12) +
        analysis.totals.testFunctions.toString().padEnd(8);
    }
    console.log(totalRow);

    // Section summary
    const fileCount = Object.keys(analysis.files).length;
    const fileType = showDeprecated ? "modules" : "test files";
    console.log(`\n📈 ${title.replace(":", "")} Summary:`);
    console.log(`• Total ${fileType}: ${fileCount}`);
    console.log(`• Raw lines: ${analysis.totals.total}`);
    console.log(`• Code lines: ${analysis.totals.code}`);
    console.log(
      `• Comment lines: ${analysis.totals.comments} (${(
        (analysis.totals.comments / analysis.totals.total) *
        100
      ).toFixed(1)}%)`
    );
    console.log(`• Blank lines: ${analysis.totals.blank}`);

    if (showDeprecated && analysis.totals.deprecated > 0) {
      console.log(
        `• Deprecated lines: ${analysis.totals.deprecated} (${(
          (analysis.totals.deprecated / analysis.totals.total) *
          100
        ).toFixed(1)}%)`
      );
    }

    if (showDeprecated && analysis.totals.testFunctions > 0) {
      console.log(
        `• Test function lines: ${analysis.totals.testFunctions} (${(
          (analysis.totals.testFunctions / analysis.totals.total) *
          100
        ).toFixed(1)}%)`
      );
    }
  }
}

// CLI handling
function main() {
  const args = process.argv.slice(2);
  const options = {};

  // Parse CLI arguments
  if (args.includes("--include-comments")) options.skipComments = false;
  if (args.includes("--include-blank")) options.skipBlankLines = false;
  if (args.includes("--include-deprecated")) options.skipDeprecated = false;
  if (args.includes("--include-test-functions"))
    options.skipTestFunctions = false;
  if (args.includes("--details")) options.showDetails = true;
  if (args.includes("--help")) {
    console.log(`
Usage: node scripts/count-loc.js [options]

Options:
  --include-comments      Include comment lines in effective count
  --include-blank         Include blank lines in effective count  
  --include-deprecated    Include deprecated lines in effective count
  --include-test-functions  Include test function lines in effective count
  --details               Show configuration details
  --help                  Show this help message

Default: Counts only code lines (skips comments, blank lines, and deprecated code)
`);
    return;
  }

  const analyzer = new MoveCodeAnalyzer(options);
  const sourcesPath = path.join(
    __dirname,
    "..",
    "packages",
    "deeptrade",
    "sources"
  );
  const testsPath = path.join(
    __dirname,
    "..",
    "packages",
    "deeptrade",
    "tests"
  );

  if (!fs.existsSync(sourcesPath)) {
    console.error("❌ Sources directory not found:", sourcesPath);
    console.log(
      "Make sure you're running this from the project root directory."
    );
    return;
  }

  try {
    // Analyze sources
    const sourcesAnalysis = analyzer.analyzeDirectory(sourcesPath);

    // Analyze tests (optional)
    let testsAnalysis = null;
    if (fs.existsSync(testsPath)) {
      testsAnalysis = analyzer.analyzeTestDirectory(testsPath);
    }

    // Display results
    analyzer.formatResults(sourcesAnalysis, testsAnalysis);
  } catch (error) {
    console.error("❌ Error analyzing files:", error.message);
  }
}

if (require.main === module) {
  main();
}

module.exports = MoveCodeAnalyzer;
