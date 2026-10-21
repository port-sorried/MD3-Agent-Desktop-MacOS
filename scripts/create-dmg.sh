#!/bin/bash
set -euo pipefail

application="${APPLICATION_PATH:-dist/MD3Agent.app}"
destination="${OUTPUT_DIRECTORY:-dist}"
version="${VERSION:-0.1.0}"
architecture="${ARCHITECTURE:-arm64}"
identity="${SIGNING_IDENTITY:--}"

if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'macos is required to create the installer image' >&2
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
if [[ ! -x "$application/Contents/MacOS/MD3Agent" ]]; then
    printf '%s\n' 'build the application with scripts/package-macos.sh first' >&2
    exit 1
fi

codesign --verify --strict --verbose=2 "$application"
staging="$(mktemp -d "${TMPDIR:-/tmp}/md3agent-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$destination"
ditto "$application" "$staging/MD3Agent.app"
ln -s /Applications "$staging/Applications"
printf '%s\n' \
    'install MD3Agent' \
    '' \
    'drag MD3Agent.app onto Applications, then open it from Applications.' \
    'requires macOS 14 or later. arm64 builds require Apple Silicon.' \
    '' \
    'development builds are ad-hoc signed, not notarized by Apple.' \
    'if macOS blocks a trusted development build, use System Settings > Privacy & Security > Open Anyway.' \
    > "$staging/Read Me.txt"

image="$destination/MD3Agent-${version}-macos-${architecture}.dmg"
hdiutil create -volname MD3Agent -srcfolder "$staging" -format UDZO -ov "$image"
if [[ "$identity" != - ]]; then
    codesign --force --timestamp --sign "$identity" "$image"
    codesign --verify --verbose=2 "$image"
fi
hdiutil verify "$image"
shasum -a 256 "$image" > "$image.sha256"
printf '%s\n' "$image"
