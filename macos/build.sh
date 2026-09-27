#!/bin/bash
# Builds build/MarkQuill.app (the Swift macOS app) (app + Quick Look extension). Needs Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")/.."  # repo root: output stays at build/MarkQuill.app
rm -rf build
C=build/MarkQuill.app/Contents
mkdir -p "$C/MacOS" "$C/Resources" "$C/PlugIns"
swiftc -O -o "$C/MacOS/MarkQuill" macos/App/main.swift
macos/build-ql.sh && cp -R build/ql/MarkQuillPreview.appex "$C/PlugIns/"
cp macos/App/Info.plist "$C/"
cp -R web "$C/Resources/"
cp src-tauri/icons/icon.icns src-tauri/icons/Assets.car "$C/Resources/" # same icon as the Tauri app (light/dark on macOS 26+)
# ponytail: ad-hoc signed, runs on this Mac only. Developer ID + notarization for public releases.
codesign -f -s - build/MarkQuill.app
echo "Built build/MarkQuill.app"
