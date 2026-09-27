#!/bin/bash
# Builds the Quick Look extension (spacebar in Finder) into build/ql/MarkQuillPreview.appex.
# Used by macos/build.sh and, on macOS, by the Tauri build (src-tauri/tauri.macos.conf.json bundles it into PlugIns/).
# Arch: $TAURI_ENV_ARCH (aarch64 / x86_64) when Tauri runs it, else this Mac's.
set -euo pipefail
cd "$(dirname "$0")/.."
arch=${TAURI_ENV_ARCH:-$(uname -m)}; [ "$arch" = arm64 ] && arch=aarch64
[ "$arch" = aarch64 ] && arch=arm64
version=$(grep -m1 '^version' src-tauri/Cargo.toml | cut -d '"' -f2)
X=build/ql/MarkQuillPreview.appex/Contents
rm -rf build/ql
mkdir -p "$X/MacOS" "$X/Resources"
swiftc -O -target "$arch-apple-macos13.0" -module-name MarkQuillPreview -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$X/MacOS/MarkQuillPreview" macos/QuickLook/PreviewViewController.swift
cp macos/QuickLook/Info.plist "$X/"
plutil -replace CFBundleShortVersionString -string "$version" "$X/Info.plist"
cp -R web "$X/Resources/"
# ponytail: ad-hoc signed with the sandbox entitlements Quick Look requires; Developer ID + notarization for Gatekeeper-clean installs
codesign -f -s - --entitlements macos/QuickLook/QL.entitlements build/ql/MarkQuillPreview.appex
echo "Built build/ql/MarkQuillPreview.appex ($arch)"
