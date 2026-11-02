#!/bin/bash
# 编译并安装到 /Applications，然后重启
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "== 安装到 /Applications =="
pkill -f "E5Keeper.app/Contents/MacOS/E5Keeper" 2>/dev/null || true
sleep 0.5
rm -rf /Applications/E5Keeper.app
cp -R build/E5Keeper.app /Applications/

echo "== 启动 =="
open /Applications/E5Keeper.app
echo "装好了：/Applications/E5Keeper.app"
