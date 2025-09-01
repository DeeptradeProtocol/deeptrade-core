#!/bin/bash

# This script automates running Sui Move tests with coverage analysis.
# It handles the temporary modification of 'Move.toml' to uncomment
# development dependencies required for the tests to build.

# Exit immediately if a command exits with a non-zero status.
set -e

MOVE_TOML_PATH="packages/deeptrade-core/Move.toml"
PACKAGE_PATH="packages/deeptrade-core"

# Function to modify Move.toml dependencies.
# $1: action ("uncomment" or "comment")
modify_deps() {
    local action=$1
    echo "Action: $action dependencies in $MOVE_TOML_PATH..."
    if [ "$action" == "uncomment" ]; then
        perl -i -pe 's/^#\s*(deepbook = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/$1/' "$MOVE_TOML_PATH"
        perl -i -pe 's/^#\s*(Pyth = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/pyth-crosschain.git".*\})/$1/' "$MOVE_TOML_PATH"
    else # comment
        perl -i -pe 's/^(deepbook = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/# $1/' "$MOVE_TOML_PATH"
        perl -i -pe 's/^(Pyth = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/pyth-crosschain.git".*\})/# $1/' "$MOVE_TOML_PATH"
    fi
}

# Ensure dependencies are re-commented on exit
trap "echo 'Cleaning up...'; modify_deps comment" EXIT

# 1. Uncomment dev dependencies
modify_deps uncomment

# 2. Run tests and generate coverage report
echo "Running tests with coverage..."
(cd "$PACKAGE_PATH" && sui move test --coverage)

# 3. Re-comment dev dependencies before generating summary
modify_deps comment

# 4. Print coverage summary
echo "Generating coverage summary..."
(cd "$PACKAGE_PATH" && sui move coverage summary)

echo ""
echo "Coverage map generated. You can now inspect coverage for a specific module."
echo "For example, to see the report for the 'pool' module, run:"
echo "(cd packages/deeptrade-core && sui move coverage source --module pool)"
echo ""

echo "Coverage script complete."
