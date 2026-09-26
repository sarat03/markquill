#!/bin/bash
# Rebuilds every app icon in src-tauri/icons/ from the sources here. Needs macOS with Xcode (actool, iconutil).
#   markquill.svg        full design, used from 64 px up
#   markquill-small.svg  simplified design for 16-32 px (taskbar, file lists), where the full one smudges
#   icon.json            Icon Composer description of the macOS 26+ icon: background colors for light and dark,
#                        plus the artwork of markquill.svg (light) and its dark version, generated below
set -euo pipefail
cd "$(dirname "$0")"
out=..
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

swiftc -O render.swift -o "$tmp/render"
r() { "$tmp/render" "$1" "$2" "$3"; } # svg, png, size

# Linux / window icons
r markquill-small.svg "$out/32x32.png" 32
r markquill.svg "$out/128x128.png" 128
r markquill.svg "$out/128x128@2x.png" 256
r markquill.svg "$out/icon.png" 512

# macOS .icns (all macOS versions; 26+ prefers Assets.car below)
set_=$tmp/icon.iconset; mkdir "$set_"
r markquill-small.svg "$set_/icon_16x16.png" 16
r markquill-small.svg "$set_/icon_16x16@2x.png" 32
r markquill-small.svg "$set_/icon_32x32.png" 32
for s in 32 128 256 512; do
  [ $s != 32 ] && r markquill.svg "$set_/icon_${s}x${s}.png" $s
  r markquill.svg "$set_/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$set_" -o "$out/icon.icns"

# Windows .ico: PNG entries, small design up to 32 px, full design above
for s in 16 24 32; do r markquill-small.svg "$tmp/ico-$s.png" $s; done
for s in 48 64 128 256; do r markquill.svg "$tmp/ico-$s.png" $s; done
python3 - "$tmp" "$out/icon.ico" <<'EOF'
import struct, sys
tmp, dst = sys.argv[1], sys.argv[2]
sizes = [16, 24, 32, 48, 64, 128, 256]
data = [open(f"{tmp}/ico-{s}.png", "rb").read() for s in sizes]
head = struct.pack("<HHH", 0, 1, len(sizes))
offset, entries = 6 + 16 * len(sizes), b""
for s, d in zip(sizes, data):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(d), offset)  # 256 is stored as 0
    offset += len(d)
open(dst, "wb").write(head + entries + b"".join(data))
EOF

# macOS 26+ light/dark icon (Assets.car). The system draws the rounded shape and the background from icon.json,
# so the artwork is markquill.svg without its background square, and a dark version with swapped colors.
icon=$tmp/AppIcon.icon; mkdir -p "$icon/Assets"
cp icon.json "$icon/"
python3 - markquill.svg "$icon/Assets" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'\s*<!-- rounded square[^\n]*\n\s*<rect x="100"[^\n]*/>', '', s)  # the system draws the icon shape
s = s.replace('viewBox="0 0 1024 1024"', 'viewBox="100 100 824 824"')        # artwork fills the icon canvas
assert 'x="100" y="100"' not in s, "background square not found in markquill.svg"
open(f"{sys.argv[2]}/art.svg", "w").write(s)
# dark: slate page, light-blue ink and nib, black shadows; the quill stays white
for a, b in [('stop-color="#FFFFFF"', 'stop-color="#34455F"'), ('#E9F1FB', '#27364C'),
             ('#1A4E8E', '#8CC4FF'), ('#153F73', '#DCEBFC'), ('#0B3A75', '#000000')]:
    s = s.replace(a, b)
open(f"{sys.argv[2]}/art-dark.svg", "w").write(s)
EOF
xcrun actool "$icon" --compile "$tmp" --platform macosx --minimum-deployment-target 26.0 \
  --app-icon AppIcon --output-partial-info-plist "$tmp/partial.plist" >/dev/null
cp "$tmp/Assets.car" "$out/Assets.car"

echo "Icons rebuilt in src-tauri/icons/"
