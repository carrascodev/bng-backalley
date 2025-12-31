#!/bin/bash
# Build and deploy to ../mods/
# Usage: ./deploy.sh <version> <type>
# Example: ./deploy.sh 0.1 alpha
# Example: ./deploy.sh dev  (deploys unpacked for runtime reload)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODS_DIR="$SCRIPT_DIR/../mods"
UNPACKED_DIR="$MODS_DIR/unpacked/car_theft_career"

# Dev mode - deploy unpacked for runtime reload
if [ "$1" = "dev" ] || [ "$1" = "--dev" ]; then
    echo "Deploying in DEV mode (unpacked)..."

    # Disable any existing backAlley ZIPs to prevent conflicts
    for zip in "$MODS_DIR"/backAlley*.zip; do
        if [ -f "$zip" ]; then
            mv "$zip" "${zip}.disabled"
            echo "Disabled $(basename "$zip")"
        fi
    done

    # Create unpacked folder structure
    mkdir -p "$UNPACKED_DIR"

    # Sync mod files (excluding test, git, build artifacts)
    rsync -av --delete \
        --exclude='.git' \
        --exclude='.gitignore' \
        --exclude='test/' \
        --exclude='*.zip' \
        --exclude='build.sh' \
        --exclude='deploy.sh' \
        --exclude='README.md' \
        "$SCRIPT_DIR/" "$UNPACKED_DIR/"

    echo "Deployed to $UNPACKED_DIR"
    echo "Reload in-game with: Ctrl+L or extensions.reload(\"carTheft_main\")"
    exit 0
fi

# Normal build mode
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <version> <type>"
    echo "       $0 dev"
    echo ""
    echo "Examples:"
    echo "  $0 0.1 alpha    - Build and deploy ZIP"
    echo "  $0 dev          - Deploy unpacked for dev (runtime reload)"
    echo ""
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
