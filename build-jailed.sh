#!/bin/bash
# 越狱设备专用：把工程编译成「无签名 IPA」（不需要 Apple 账号 / 证书）。
# 用法：在 Mac 上 `./build-jailed.sh`，产物为当前目录下的 CreditCardManager.ipa
set -euo pipefail

cd "$(dirname "$0")"

echo "==> [1/4] 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> [2/4] 无签名编译 (iphoneos, Release)"
xcodebuild \
  -project CreditCardManager.xcodeproj \
  -target CreditCardManager \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="CreditCardManager.jailed.entitlements" \
  build

echo "==> [3/4] 定位 .app"
APP_PATH=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "错误：未找到编译产物 .app"
  exit 1
fi
echo "    找到: $APP_PATH"

echo "==> [4/4] 打包成 IPA (Payload/*.app)"
rm -rf Payload "$PWD/CreditCardManager.ipa"
mkdir -p Payload
cp -R "$APP_PATH" "Payload/$(basename "$APP_PATH")"
zip -r CreditCardManager.ipa Payload >/dev/null

echo ""
echo "完成 ✅  IPA 路径: $PWD/CreditCardManager.ipa"
echo "将该 IPA 用越狱安装工具（AppSync / Sideloadly / Filza 等）装入设备即可。"
