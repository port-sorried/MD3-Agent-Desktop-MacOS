#!/bin/bash
set -euo pipefail

configuration="${CONFIGURATION:-release}"
architecture="${ARCHITECTURE:-arm64}"
version="${VERSION:-0.1.0}"
destination="${OUTPUT_DIRECTORY:-dist}"
identity="${SIGNING_IDENTITY:--}"

if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'macos is required to package this application' >&2
    exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    printf '%s\n' 'VERSION must be a semantic version' >&2
    exit 1
fi
if [[ "$architecture" != arm64 && "$architecture" != x86_64 ]]; then
    printf '%s\n' 'ARCHITECTURE must be arm64 or x86_64' >&2
    exit 1
fi

swift build -c "$configuration" --arch "$architecture"
binary_directory="$(swift build -c "$configuration" --arch "$architecture" --show-bin-path)"
application="$destination/MD3Agent.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
install -m 755 "$binary_directory/MD3Agent" "$application/Contents/MacOS/MD3Agent"
install -m 644 Info.plist "$application/Contents/Info.plist"
install -m 644 LICENSE "$application/Contents/Resources/LICENSE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$application/Contents/Info.plist"

if [[ "$identity" == - ]]; then
    codesign --force --sign - --entitlements MD3Agent.entitlements "$application"
else
    codesign --force --options runtime --timestamp --sign "$identity" --entitlements MD3Agent.entitlements "$application"
fi
codesign --verify --strict --verbose=2 "$application"
printf '%s\n' "$application"
