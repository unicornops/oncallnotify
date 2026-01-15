#!/bin/bash
#
# Build script for Mac App Store distribution
# This creates an archive suitable for upload to App Store Connect
#
# Usage:
#   ./build-appstore.sh [version]
#
# Requirements:
#   - "3rd Party Mac Developer Application" certificate installed
#   - "3rd Party Mac Developer Installer" certificate installed
#   - Provisioning profile for the app
#   - Xcode command line tools
#
# Output:
#   - build/AppStore/OnCallNotify.xcarchive - Archive for App Store
#   - build/AppStore/OnCallNotify.pkg - Signed package ready for upload
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Configuration
SCHEME="OnCallNotify"
PROJECT="OnCallNotify.xcodeproj"
BUNDLE_ID="ie.unicornops.oncallnotify"
BUILD_DIR="build/AppStore"
ARCHIVE_PATH="${BUILD_DIR}/${SCHEME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
PKG_PATH="${BUILD_DIR}/${SCHEME}.pkg"

echo -e "${GREEN}=== Mac App Store Build Script ===${NC}"
echo ""

# Verify we have the required certificates
echo "Checking for required certificates..."
if ! security find-identity -v -p codesigning | grep -q "3rd Party Mac Developer Application"; then
    echo -e "${RED}Error: '3rd Party Mac Developer Application' certificate not found${NC}"
    echo "You need to download this certificate from Apple Developer Portal"
    echo "and install it in your keychain."
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -q "3rd Party Mac Developer Installer"; then
    echo -e "${RED}Error: '3rd Party Mac Developer Installer' certificate not found${NC}"
    echo "You need to download this certificate from Apple Developer Portal"
    echo "and install it in your keychain."
    exit 1
fi

echo -e "${GREEN}✓ Found required certificates${NC}"
echo ""

# Extract certificate identities
APP_IDENTITY=$(security find-identity -v -p codesigning | grep "3rd Party Mac Developer Application" | head -1 | sed -n 's/.*"\(.*\)"/\1/p')
INSTALLER_IDENTITY=$(security find-identity -v -p codesigning | grep "3rd Party Mac Developer Installer" | head -1 | sed -n 's/.*"\(.*\)"/\1/p')

echo "Using certificates:"
echo "  App: $APP_IDENTITY"
echo "  Installer: $INSTALLER_IDENTITY"
echo ""

# Clean build directory
echo "Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
echo ""

# Archive the app
echo "Creating archive for App Store..."
echo "This may take a few minutes..."
echo ""

xcodebuild archive \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -archivePath "${ARCHIVE_PATH}" \
    -configuration Release \
    CODE_SIGN_IDENTITY="${APP_IDENTITY}" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="OnCallNotify App Store" \
    CODE_SIGN_ENTITLEMENTS="OnCallNotify/OnCallNotify.AppStore.entitlements" \
    ENABLE_HARDENED_RUNTIME=NO \
    | grep -v "^$" || true  # Filter empty lines, don't fail on grep

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo -e "${RED}Error: Archive creation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Archive created successfully${NC}"
echo ""

# Export for App Store
echo "Exporting for App Store..."
echo ""

# Create export options plist
cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
    | grep -v "^$" || true

if [ ! -f "${EXPORT_PATH}/${SCHEME}.pkg" ]; then
    echo -e "${RED}Error: Export failed - no PKG created${NC}"
    echo "Check ExportOptions.plist and ensure your team ID is correct"
    exit 1
fi

# Move PKG to build directory
mv "${EXPORT_PATH}/${SCHEME}.pkg" "${PKG_PATH}"

echo -e "${GREEN}✓ Package created successfully${NC}"
echo ""

# Get app info from archive
echo "=== Build Information ==="
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${SCHEME}.app"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"

if [ -f "${PLIST_PATH}" ]; then
    BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH")
    BUNDLE_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH")

    echo "Bundle ID: ${BUNDLE_ID}"
    echo "Version: ${BUNDLE_VERSION}"
    echo "Build: ${BUNDLE_BUILD}"
    echo ""
fi

# Verify package signature
echo "Verifying package signature..."
pkgutil --check-signature "${PKG_PATH}"
echo ""

echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Archive: ${ARCHIVE_PATH}"
echo "Package: ${PKG_PATH}"
echo ""
echo "Next steps:"
echo "1. Validate the package:"
echo "   xcrun altool --validate-app -f ${PKG_PATH} -t macos --apiKey YOUR_KEY --apiIssuer YOUR_ISSUER"
echo ""
echo "2. Upload to App Store Connect:"
echo "   xcrun altool --upload-app -f ${PKG_PATH} -t macos --apiKey YOUR_KEY --apiIssuer YOUR_ISSUER"
echo ""
echo "   OR use Transporter app (recommended)"
echo ""
echo "3. Go to App Store Connect to complete submission"
echo ""
