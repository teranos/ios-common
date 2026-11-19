#!/bin/sh
# An IPA, to App Store Connect, named by what its own Info.plist says.
#
#     upload.sh IPA
#
# Reads APPLE_API_KEY, APPLE_API_ISSUER, APPLE_API_KEY_CONTENT and
# APPLE_APP_ID (the app's Apple ID in App Store Connect) from the environment.
# Prints BUILD=<CFBundleVersion>, for delivered.py wait.
set -eu
ipa=$1
mkdir -p ~/.appstoreconnect/private_keys
echo "$APPLE_API_KEY_CONTENT" | base64 --decode > ~/.appstoreconnect/private_keys/AuthKey_"$APPLE_API_KEY".p8
plist=$(mktemp)
unzip -p "$ipa" 'Payload/*.app/Info.plist' > "$plist"
bundle=$(plutil -extract CFBundleIdentifier raw "$plist")
build=$(plutil -extract CFBundleVersion raw "$plist")
short=$(plutil -extract CFBundleShortVersionString raw "$plist")
echo "uploading $bundle $short ($build)" >&2
xcrun altool --upload-package "$ipa" --type ios \
  --apple-id "$APPLE_APP_ID" --bundle-id "$bundle" \
  --bundle-version "$build" --bundle-short-version-string "$short" \
  --api-key "$APPLE_API_KEY" --api-issuer "$APPLE_API_ISSUER" >&2
echo "BUILD=$build"
