#!/bin/bash
# Builds build/MDView.app (app + Quick Look extension). Needs Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
C=build/MDView.app/Contents
X=$C/PlugIns/MDPreview.appex/Contents
mkdir -p "$C/MacOS" "$C/Resources" "$X/MacOS" "$X/Resources"
swiftc -O -o "$C/MacOS/MDView" App/main.swift
swiftc -O -module-name MDPreview -application-extension -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$X/MacOS/MDPreview" QL/PreviewViewController.swift
cp App/Info.plist "$C/"; cp QL/Info.plist "$X/"
cp -R web "$C/Resources/"; cp -R web "$X/Resources/"
# ponytail: ad-hoc signed, runs on this Mac only. Developer ID + notarization for public releases.
codesign -f -s - --entitlements QL/QL.entitlements "$C/PlugIns/MDPreview.appex"
codesign -f -s - build/MDView.app
echo "Built build/MDView.app"
