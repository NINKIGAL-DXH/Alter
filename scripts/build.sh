#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${ALTER_VERSION:-0.1.0}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][a-zA-Z0-9]+)*$ ]] || { echo 'Invalid version'; exit 1; }
arch="${ALTER_ARCH:-$(uname -m)}"
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || exit 1
swift build -c release --arch "$arch" --jobs 2
bin_dir=$(swift build -c release --arch "$arch" --show-bin-path)
destination="dist/$arch/Alter.app"
[[ ! -e "$destination" ]] || { echo "Staging already exists: $destination"; exit 1; }
staging=$(mktemp -d "${TMPDIR:-/tmp}/alter-build.XXXXXX")
app="$staging/Alter.app"
# Use a fresh staging directory; never recursively remove a caller-provided path.
[[ ! -e "$app" ]] || { echo "Staging exists: $app. Move it aside before rebuilding."; exit 1; }
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Alter" "$app/Contents/MacOS/Alter"
cp -RX "$bin_dir/Alter_AlterApp.bundle" "$app/Contents/Resources/"
iconset=$(mktemp -d "${TMPDIR:-/tmp}/alter-icon.XXXXXX")
mkdir "$iconset/Alter.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Sources/AlterApp/Resources/Brand/Alter.png --out "$iconset/Alter.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Sources/AlterApp/Resources/Brand/Alter.png --out "$iconset/Alter.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset/Alter.iconset" -o "$app/Contents/Resources/Alter.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.ninkigal-dxh.Alter</string>
<key>CFBundleName</key><string>Alter</string>
<key>CFBundleDisplayName</key><string>Alter</string>
<key>CFBundleExecutable</key><string>Alter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Alter</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDownloadsFolderUsageDescription</key><string>只读查找旧安装包，仅在逐项确认后移入废纸篓。</string>
<key>NSDocumentsFolderUsageDescription</key><string>仅在你选择文稿目录后只读分析空间。</string>
<key>NSDesktopFolderUsageDescription</key><string>仅在你选择桌面后只读分析空间。</string>
<key>NSHumanReadableCopyright</key><string>Alter contributors. Mole core © tw93 and contributors, GPL-3.0. Character artwork belongs to its respective owners.</string>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
# Strip only incompatible build metadata, never quarantine or security flags.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/Alter" --smoke-test
mkdir -p "dist/$arch"
cp -RX "$app" "$destination"
echo "Built $destination"
