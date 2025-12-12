#!/bin/bash

# OnCall Notify Build Script
# This script builds the OnCall Notify macOS application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}OnCall Notify - Build Script${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Configuration
PROJECT_NAME="OnCallNotify"
SCHEME_NAME="OnCallNotify"
CONFIGURATION="${1:-Release}"
BUILD_DIR="build"

echo -e "${YELLOW}Configuration:${NC} $CONFIGURATION"
echo -e "${YELLOW}Project:${NC} $PROJECT_NAME"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: xcodebuild not found. Please install Xcode.${NC}"
    exit 1
fi

# Check if project file exists
if [ ! -f "${PROJECT_NAME}.xcodeproj/project.pbxproj" ]; then
    echo -e "${RED}Error: Project file not found at ${PROJECT_NAME}.xcodeproj${NC}"
    exit 1
fi

echo -e "${GREEN}Building ${PROJECT_NAME}...${NC}\n"

# Clean previous builds
if [ -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Cleaning previous build...${NC}"
    rm -rf "$BUILD_DIR"
fi

# Build the project
xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    SYMROOT="$BUILD_DIR" \
    build

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build successful!${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    # Find the built app
    APP_PATH=$(find "$BUILD_DIR" -name "${PROJECT_NAME}.app" -type d | head -n 1)

    if [ -n "$APP_PATH" ]; then
        echo -e "${GREEN}Application built at:${NC}"
        echo -e "  $APP_PATH"
        echo ""
        echo -e "${YELLOW}To run the application:${NC}"
        echo -e "  open \"$APP_PATH\""
        echo ""
        echo -e "${YELLOW}To install to Applications folder:${NC}"
        echo -e "  cp -r \"$APP_PATH\" /Applications/"
        echo ""
    fi
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Build failed!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
