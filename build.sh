#!/bin/bash
# Build backAlley.{version}-{releaseType}.zip with files at root level
# Usage: ./build.sh <version> <type>
# Example: ./build.sh 0.1 alpha -> backAlley.0.1-alpha.zip

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <version> <type>"
    echo "Example: $0 0.1 alpha"
    echo "Types: alpha, beta, release"
    exit 1
fi

VERSION="$1"
TYPE="$2"
ZIP_NAME="backAlley.${VERSION}-${TYPE}.zip"

cd "$SCRIPT_DIR"

# Remove old zip if exists
rm -f "$ZIP_NAME"

# Create zip with mod contents at root (not inside parent folder)
zip -r "$ZIP_NAME" info.json lua/ scripts/ ui/ settings/ -x "*.git*"

echo "Built $ZIP_NAME ($(du -h "$ZIP_NAME" | cut -f1))"
