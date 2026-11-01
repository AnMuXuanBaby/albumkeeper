#!/usr/bin/env bash
# 在 macOS 上编译出未签名的 .ipa（供 TrollStore 安装）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AlbumKeeper"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="$ROOT/build"
APP_DIR="$OUT/Payload/$APP_NAME.app"

rm -rf "$OUT"
rm -f "$ROOT/$APP_NAME.ipa"
mkdir -p "$APP_DIR"

echo "使用 SDK: $SDK"
xcodebuild -version || true

xcrun --sdk iphoneos swiftc \
  -sdk "$SDK" \
  -target arm64-apple-ios16.0 \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  -framework SwiftUI \
  -framework UIKit \
  -framework Photos \
  -framework PhotosUI \
  -framework AVKit \
  -framework AVFoundation \
  -framework Vision \
  -framework CoreLocation \
  -o "$APP_DIR/$APP_NAME" \
  "$ROOT"/Sources/*.swift

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Info.plist"
cp "$ROOT/Resources/AppIcon.png" "$APP_DIR/AppIcon.png"
cp "$ROOT/Resources/AppIcon60x60@2x.png" "$APP_DIR/AppIcon60x60@2x.png"
cp "$ROOT/Resources/AppIcon60x60@3x.png" "$APP_DIR/AppIcon60x60@3x.png"

chmod +x "$APP_DIR/$APP_NAME"

cd "$OUT"
zip -qry "$ROOT/$APP_NAME.ipa" Payload

echo "已生成: $ROOT/$APP_NAME.ipa"
ls -lh "$ROOT/$APP_NAME.ipa"
