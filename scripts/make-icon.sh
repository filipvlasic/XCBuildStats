#!/usr/bin/env bash
#
# Generates the AppIcon asset catalog from a single 1024x1024 PNG.
#   ./scripts/make-icon.sh [source.png]   (default: Resources/AppIcon-source-1024.png)
#
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-Resources/AppIcon-source-1024.png}"
CATALOG="Resources/Assets.xcassets"
SET="$CATALOG/AppIcon.appiconset"

mkdir -p "$SET"
for s in 16 32 64 128 256 512 1024; do
  sips -z "$s" "$s" "$SRC" --out "$SET/icon_${s}.png" >/dev/null
done

cat > "$CATALOG/Contents.json" <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON

cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "size" : "16x16",   "scale" : "1x", "filename" : "icon_16.png" },
    { "idiom" : "mac", "size" : "16x16",   "scale" : "2x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "1x", "filename" : "icon_32.png" },
    { "idiom" : "mac", "size" : "32x32",   "scale" : "2x", "filename" : "icon_64.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "1x", "filename" : "icon_128.png" },
    { "idiom" : "mac", "size" : "128x128", "scale" : "2x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "1x", "filename" : "icon_256.png" },
    { "idiom" : "mac", "size" : "256x256", "scale" : "2x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "1x", "filename" : "icon_512.png" },
    { "idiom" : "mac", "size" : "512x512", "scale" : "2x", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Wrote $SET"
