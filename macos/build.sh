#!/bin/bash
# Builds build/MarkQuill.app (the Swift macOS app) (app + Quick Look extension). Needs Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")/.."  # repo root: output stays at build/MarkQuill.app
rm -rf build
C=build/MarkQuill.app/Contents
X=$C/PlugIns/MarkQuillPreview.appex/Contents
mkdir -p "$C/MacOS" "$C/Resources" "$X/MacOS" "$X/Resources"
swiftc -O -o "$C/MacOS/MarkQuill" macos/App/main.swift
swiftc -O -module-name MarkQuillPreview -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$X/MacOS/MarkQuillPreview" macos/QuickLook/PreviewViewController.swift
cp macos/App/Info.plist "$C/"; cp macos/QuickLook/Info.plist "$X/"
cp -R web "$C/Resources/"; cp -R web "$X/Resources/"
# ponytail: ad-hoc signed, runs on this Mac only. Developer ID + notarization for public releases.
codesign -f -s - --entitlements macos/QuickLook/QL.entitlements "$C/PlugIns/MarkQuillPreview.appex"
codesign -f -s - build/MarkQuill.app
echo "Built build/MarkQuill.app"
