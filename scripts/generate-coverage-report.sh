#!/bin/bash

# This script generates detailed, per-module HTML coverage reports for the
# deeptrade-core package. It automates the dependency management in Move.toml,
# runs tests to generate a coverage map, and then creates an HTML report for
# each module using 'aha'.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
MOVE_TOML_PATH="packages/deeptrade-core/Move.toml"
PACKAGE_PATH="packages/deeptrade-core"
SOURCES_PATH="$PACKAGE_PATH/sources"
REPORTS_DIR="$PACKAGE_PATH/coverage-reports"

# --- Helper Functions ---

# Function to modify Move.toml dependencies.
# $1: action ("uncomment" or "comment")
modify_deps() {
    local action=$1
    echo "=> $action dependencies in $MOVE_TOML_PATH"
    if [ "$action" == "uncomment" ]; then
        perl -i -pe 's/^#\s*(deepbook = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/$1/' "$MOVE_TOML_PATH"
        perl -i -pe 's/^#\s*(Pyth = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/pyth-crosschain.git".*\})/$1/' "$MOVE_TOML_PATH"
    else # comment
        perl -i -pe 's/^(deepbook = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/deepbookv3.git".*\})/# $1/' "$MOVE_TOML_PATH"
        perl -i -pe 's/^(Pyth = \{ git = "https:\/\/github.com\/DeeptradeProtocol\/pyth-crosschain.git".*\})/# $1/' "$MOVE_TOML_PATH"
    fi
}

# Check for 'aha' command
check_aha() {
    if ! command -v aha &> /dev/null; then
        echo "Error: 'aha' is not installed. Please install it to generate HTML reports."
        echo "On macOS: brew install aha"
        echo "On Debian/Ubuntu: sudo apt-get install aha"
        exit 1
    fi
}

# --- Main Script ---

# 0. Check for dependencies
check_aha

# Ensure dependencies are re-commented on exit, even if the script fails
trap "echo '=> Cleaning up...'; modify_deps comment" EXIT

# 1. Uncomment dev dependencies
modify_deps uncomment

# 2. Run tests to generate the coverage map
echo "=> Running tests to generate coverage map... (this can take a few minutes)"
# We are showing the full test output so you can see the progress.
(cd "$PACKAGE_PATH" && sui move test --coverage)
echo "=> Test run complete."

# 3. Re-comment dependencies now that the coverage map is created
modify_deps comment

# 4. Create the coverage reports directory
echo "=> Creating reports directory: $REPORTS_DIR"
mkdir -p "$REPORTS_DIR"

# 5. Generate a report for each module
echo "=> Generating per-module HTML coverage reports..."
for module_file in "$SOURCES_PATH"/*.move; do
    module_name=$(basename "$module_file" .move)
    report_file="$REPORTS_DIR/$module_name.html"
    echo "   - Generating report for '$module_name' module..."
    # We use `script -q /dev/null` to trick the sui command into thinking
    # it's running in a real terminal, which forces it to output color codes.
    (cd "$PACKAGE_PATH" && script -q /dev/null sui move coverage source --module "$module_name") | aha > "$report_file"
done

# 6. Generate an index file for easy navigation
echo "=> Generating index.html..."
cat > "$REPORTS_DIR/index.html" <<- EOM
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Deeptrade Core Coverage Report</title>
    <style>
        body { font-family: sans-serif; margin: 2em; background-color: #f8f9fa; color: #212529; }
        h1 { color: #0056b3; }
        ul { list-style-type: none; padding: 0; }
        li { margin: 0.5em 0; }
        a { text-decoration: none; color: #007bff; }
        a:hover { text-decoration: underline; }
        .container { max-width: 800px; margin: auto; padding: 2em; background-color: #fff; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <div class="container">
        <h1>Deeptrade Core Coverage Report</h1>
        <p>Select a module to view its detailed test coverage report.</p>
        <ul>
EOM

for module_file in "$SOURCES_PATH"/*.move; do
    module_name=$(basename "$module_file" .move)
    echo "            <li><a href=\"$module_name.html\">$module_name</a></li>" >> "$REPORTS_DIR/index.html"
done

cat >> "$REPORTS_DIR/index.html" <<- EOM
        </ul>
    </div>
</body>
</html>
EOM

echo "✅ All reports generated successfully in '$REPORTS_DIR'."
echo ""
echo "To view the reports, you can start a simple web server:"
echo "cd '$REPORTS_DIR' && python3 -m http.server"
echo "Then open http://localhost:8000 in your browser."
