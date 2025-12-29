#!/bin/bash
# Build and deploy to ../mods/
# Usage: ./deploy.sh <version> <type>
# Example: ./deploy.sh 0.1 alpha

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODS_DIR="$SCRIPT_DIR/../mods"

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <version> <type>"
    echo "Example: $0 0.1 alpha"
    echo "Types: alpha, beta, release"
    exit 1
fi

VERSION="$1"
TYPE="$2"
ZIP_NAME="backAlley.${VERSION}-${TYPE}.zip"

# Build first
"$SCRIPT_DIR/build.sh" "$VERSION" "$TYPE"

# Create mods folder if needed
mkdir -p "$MODS_DIR"

# Copy to mods folder (replacing if exists)
cp -f "$SCRIPT_DIR/$ZIP_NAME" "$MODS_DIR/$ZIP_NAME"

echo "Deployed to $MODS_DIR/$ZIP_NAME"
