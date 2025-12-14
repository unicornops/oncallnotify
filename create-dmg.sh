#!/bin/bash

# DMG Creation Script for OnCall Notify
# Creates a DMG with custom icon positioning and larger icons

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
APP_PATH="$1"
DMG_NAME="$2"
VOLUME_NAME="$3"

if [ -z "$APP_PATH" ] || [ -z "$DMG_NAME" ] || [ -z "$VOLUME_NAME" ]; then
    echo -e "${RED}Usage: $0 <app-path> <dmg-name> <volume-name>${NC}"
    echo "Example: $0 build/Release/OnCallNotify.app OnCallNotify-1.0.0.dmg 'OnCall Notify 1.0.0'"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: App not found at $APP_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Creating DMG: $DMG_NAME${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Configuration
STAGING_DIR="dmg-staging"
TEMP_DMG="temp.dmg"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# Icon size (128x128 pixels is 2x the default 64x64)
ICON_SIZE=128

# Extract app name from path
APP_NAME=$(basename "$APP_PATH")

# Clean up any existing staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo -e "${YELLOW}Copying application...${NC}"
cp -r "$APP_PATH" "$STAGING_DIR/"

echo -e "${YELLOW}Creating Applications symlink...${NC}"
ln -s /Applications "$STAGING_DIR/Applications"

echo -e "${YELLOW}Creating temporary DMG...${NC}"
# Create a temporary DMG with extra space for icon customization
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDRW \
    "$TEMP_DMG"

echo -e "${YELLOW}Mounting temporary DMG...${NC}"
# Mount the temporary DMG
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG")
DEVICE=$(echo "$MOUNT_OUTPUT" | grep -o '/dev/disk[0-9]*' | head -n 1)

# Validate device was extracted
if [ -z "$DEVICE" ]; then
    echo -e "${RED}Error: Failed to extract device from mount output${NC}"
    echo "Mount output: $MOUNT_OUTPUT"
    exit 1
fi

echo "Mounted device: $DEVICE"

# Wait for mount to complete (poll for mount directory with timeout)
TIMEOUT=10  # seconds
INTERVAL=0.2
ELAPSED=0
while [ ! -d "$MOUNT_DIR" ] && (( $(echo "$ELAPSED < $TIMEOUT" | bc -l) )); do
    sleep "$INTERVAL"
    ELAPSED=$(echo "$ELAPSED + $INTERVAL" | bc)
done

# Check if mount was successful
if [ ! -d "$MOUNT_DIR" ]; then
    echo -e "${RED}Error: Failed to mount DMG at $MOUNT_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Customizing DMG window...${NC}"

# Create the AppleScript to customize the DMG window
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        
        -- Set window properties
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        
        -- Set window bounds (left, top, right, bottom)
        -- Creates a 600x400 window
        set the bounds of container window to {100, 100, 700, 500}
        
        -- Set icon view options
        set opts to the icon view options of container window
        set icon size of opts to $ICON_SIZE
        set arrangement of opts to not arranged
        
        -- Position icons
        -- OnCallNotify.app on the left
        set position of item "$APP_NAME" to {150, 200}
        -- Applications folder on the right
        set position of item "Applications" to {450, 200}
        
        -- Update and close
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Sync to ensure all changes are written
sync

echo -e "${YELLOW}Unmounting temporary DMG...${NC}"
# Unmount the temporary DMG
if ! hdiutil detach "$DEVICE"; then
    echo -e "${YELLOW}Warning: Failed to detach cleanly, forcing...${NC}"
    if ! hdiutil detach "$DEVICE" -force; then
        echo -e "${RED}Error: Failed to detach DMG device $DEVICE${NC}"
        exit 1
    fi
fi

# Wait for unmount to complete by polling for device detachment (max 30s)
TIMEOUT=30
INTERVAL=0.5
ELAPSED=0
while hdiutil info | grep -q "$DEVICE"; do
    if (( $(echo "$ELAPSED >= $TIMEOUT" | bc -l) )); then
        echo -e "${RED}Error: Device $DEVICE did not detach after $TIMEOUT seconds${NC}"
        exit 1
    fi
    sleep $INTERVAL
    ELAPSED=$(echo "$ELAPSED + $INTERVAL" | bc)
done

echo -e "${YELLOW}Converting to compressed DMG...${NC}"
# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_NAME"

# Clean up
echo -e "${YELLOW}Cleaning up...${NC}"
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

if [ -f "$DMG_NAME" ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ DMG created successfully!${NC}"
    echo -e "${GREEN}========================================${NC}\n"
    echo -e "${GREEN}DMG:${NC} $DMG_NAME"
    echo -e "${GREEN}Size:${NC} $(ls -lh "$DMG_NAME" | awk '{print $5}')"
    echo ""
else
    echo -e "${RED}Error: DMG creation failed${NC}"
    exit 1
fi
