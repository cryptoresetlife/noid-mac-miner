#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build-gpu.command
app='dist/NOID Miner.app'
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/miner/bin"
xcrun swiftc -O -target arm64-apple-macos13.0 -parse-as-library App.swift Engine.swift -o "$app/Contents/MacOS/NOIDMiner" -framework SwiftUI -framework AppKit -framework Network -framework Foundation
cp bin/noid-metal "$app/Contents/Resources/miner/bin/"
cp oracle/target/release/noid-metal-oracle "$app/Contents/Resources/miner/bin/noid-cpu"
cp noid.metal tables.bin rounds.bin rounds-tower.bin tower-small.metal "$app/Contents/Resources/miner/"
cp source/LICENSE source/NOTICE "$app/Contents/Resources/"
cp README.md "$app/Contents/Resources/使用说明.md"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NOIDMiner</string>
<key>CFBundleIdentifier</key><string>local.noid.metalminer</string>
<key>CFBundleName</key><string>NOID Miner</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/NOID-Miner-AppleSilicon.zip
shasum -a 256 dist/NOID-Miner-AppleSilicon.zip > dist/SHA256SUMS
