#!/bin/bash
# Archive, Developer ID sign, notarize and staple MouseControl.app.
#
# One-time setup:
#   1. Config/Local.xcconfig with your DEVELOPMENT_TEAM (see Config/Local.xcconfig.example).
#   2. A "Developer ID Application" certificate for that team in the login keychain.
#   3. xcrun notarytool store-credentials MouseControlNotary --apple-id <id> --team-id <team-id>
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD=build/release
PROFILE="${NOTARY_PROFILE:-MouseControlNotary}"

rm -rf "$BUILD"
xcodebuild -project MouseControl.xcodeproj -scheme MouseControl -configuration Release \
  -archivePath "$BUILD/MouseControl.xcarchive" archive
xcodebuild -exportArchive -archivePath "$BUILD/MouseControl.xcarchive" \
  -exportOptionsPlist Scripts/ExportOptions.plist -exportPath "$BUILD"

APP="$BUILD/MouseControl.app"
codesign --verify --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$BUILD/MouseControl.zip"
xcrun notarytool submit "$BUILD/MouseControl.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
ditto -c -k --keepParent "$APP" "$BUILD/MouseControl.zip"
echo "Notarized: $APP"
