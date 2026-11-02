#!/bin/bash
# 编译 E5Keeper.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/E5Keeper.app"

echo "== 编译 =="
swift build -c release --disable-sandbox

echo "== 打包 =="
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/E5Keeper "$APP/Contents/MacOS/E5Keeper"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "== 图标 =="
if swift make_icon.swift build/icon_1024.png >/dev/null 2>&1 && [ -f build/icon_1024.png ]; then
  mkdir -p build/AppIcon.iconset
  for s in 16 32 64 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
else
  echo "图标生成跳过"
fi

echo "== 签名 =="
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "ad-hoc 签名跳过"

echo "== 完成 =="
du -sh "$APP" | awk '{print "体积：" $1}'
echo "运行：open $APP"
