#!/bin/bash
# 越狱设备专用：把工程编译成「无签名 IPA」（不需要 Apple 账号 / 证书）。
# 用法：在 Mac 上 `./build-jailed.sh`，产物为当前目录下的 CreditCardManager.ipa
set -euo pipefail

cd "$(dirname "$0")"

echo "==> [1/5] 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> [2/5] 关闭 scheme 中可能存在的签名配置"
# XcodeGen 默认会给 scheme 注入 Signing 行为；我们是无签名构建，强制覆盖。
# 这一步在 xcodebuild 命令里通过 settings 也能完成。

echo "==> [3/5] 无签名编译 (iphoneos, Release, scheme)"
# 关键：用 -scheme 而非 -target；xcodebuild 14+ 在指定 -derivedDataPath 时要求 -scheme/-testProductsPath/-xcTestrun。
# 同时指定 SDK 为 iphoneos、用空 CODE_SIGN_IDENTITY 与 ENTITLEMENTS 走纯本地/越狱路径。
xcodebuild \
  -project CreditCardManager.xcodeproj \
  -scheme CreditCardManager \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="CreditCardManager.jailed.entitlements" \
  build

echo "==> [4/5] 定位 .app"
APP_PATH=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "错误：未找到编译产物 .app"
  exit 1
fi
echo "    找到: $APP_PATH"

echo "==> [5/5] 打包成 IPA (Payload/*.app)"
rm -rf Payload "$PWD/CreditCardManager.ipa"
mkdir -p Payload
cp -R "$APP_PATH" "Payload/$(basename "$APP_PATH")"
zip -r CreditCardManager.ipa Payload >/dev/null

echo ""
echo "完成 ✅  IPA 路径: $PWD/CreditCardManager.ipa"
echo "将该 IPA 用越狱安装工具（AppSync / Sideloadly / Filza 等）装入设备即可。"
