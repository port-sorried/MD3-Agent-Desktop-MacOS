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
icon_source="app/src/main/resources/icons/md3-agent.png"
icon_directory="$(mktemp -d "${TMPDIR:-/tmp}/md3agent-icon.XXXXXX")"
trap 'rm -rf "$icon_directory"' EXIT
iconset="$icon_directory/MD3Agent.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" > /dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$iconset" -o "$application/Contents/Resources/MD3Agent.icns"
test -s "$application/Contents/Resources/MD3Agent.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$application/Contents/Info.plist"

if [[ "$identity" == - ]]; then
    codesign --force --sign - --entitlements MD3Agent.entitlements "$application"
else
    codesign --force --options runtime --timestamp --sign "$identity" --entitlements MD3Agent.entitlements "$application"
fi
codesign --verify --strict --verbose=2 "$application"
printf '%s\n' "$application"
