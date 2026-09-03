#!/bin/bash
# 越狱设备专用：把工程编译成「无签名 IPA」（不需要 Apple 账号 / 证书）。
# 用法：在 Mac 上 `./build-jailed.sh`，产物为当前目录下的 CreditCardManager.ipa
# 注意：本脚本的所有输出（含 xcodebuild 与打包步骤）由调用方统一重定向到 build.log，
#       这样无论成功与否，build.log 都能完整反映全过程，便于云端 CI 排错。
set -uo pipefail

cd "$(dirname "$0")"

echo "==> [1/5] 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> [2/5] 跳过 scheme 签名配置（由 xcodebuild 的 settings 完成）"

echo "==> [3/5] 无签名编译 (iphoneos, Release, scheme)"
# -scheme（而非 -target）配合 -derivedDataPath，是 Xcode 14+ 的硬规则。
# -destination 'generic/platform=iOS' 让 xcodebuild 不必连真机即可编译 Release。
# 同时关闭代码签名 + 指向越狱专用 entitlements 文件。
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
XCB_EXIT=$?
echo "    xcodebuild exit=$XCB_EXIT"
if [ $XCB_EXIT -ne 0 ]; then
  echo "xcodebuild 编译失败 (exit=$XCB_EXIT)"
  exit $XCB_EXIT
fi

echo "==> [4/5] 定位 .app"
echo "    诊断：列出 Products 目录"
ls -la build/Build/Products/Release-iphoneos/ || true
APP_PATH=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -n 1)
if [ -z "$APP_PATH" ]; then
  echo "错误：未找到编译产物 .app（请检查上面的 ls 输出）"
  exit 1
fi
echo "    找到: $APP_PATH"

echo "==> [5/5] 打包成 IPA (Payload/*.app)"
rm -rf Payload "$PWD/CreditCardManager.ipa"
mkdir -p Payload
cp -R "$APP_PATH" "Payload/$(basename "$APP_PATH")"
if [ ! -d "Payload/$(basename "$APP_PATH")" ]; then
  echo "错误：复制 .app 到 Payload 失败"
  exit 1
fi
zip -r CreditCardManager.ipa Payload >/dev/null
if [ ! -f "CreditCardManager.ipa" ]; then
  echo "错误：zip 生成 CreditCardManager.ipa 失败"
  exit 1
fi

echo ""
echo "完成 ✅  IPA 路径: $PWD/CreditCardManager.ipa"
echo "将该 IPA 用越狱安装工具（AppSync / Sideloadly / Filza 等）装入设备即可。"
