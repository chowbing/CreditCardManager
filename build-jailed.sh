#!/bin/bash
# 越狱设备专用：把工程编译成「无签名 IPA」（不需要 Apple 账号 / 证书）。
# 用法：在 Mac 上 `./build-jailed.sh`，产物为当前目录下的 CreditCardManager.ipa
set -uo pipefail   # 移除 -e：编译失败时不要中途退出，要能完整打印错误日志

cd "$(dirname "$0")"

echo "==> [1/5] 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> [2/5] 关闭 scheme 中可能存在的签名配置（由 xcodebuild 命令的 settings 完成）"

echo "==> [3/5] 无签名编译 (iphoneos, Release, scheme)"
# -scheme（而非 -target）配合 -derivedDataPath，是 Xcode 14+ 的硬规则。
# -destination 'generic/platform=iOS' 让 xcodebuild 不必连真机即可编译 Release。
# 同时关闭代码签名 + 指向越狱专用 entitlements 文件。
LOG_FILE="$(pwd)/build.log"
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
  build >"$LOG_FILE" 2>&1
XCB_EXIT=$?
echo "    xcodebuild exit=$XCB_EXIT，完整日志已写入 $LOG_FILE"

# 显式打印错误行（不论是否成功，便于定位）
echo "---- compile errors (最多 80 行) ----"
grep -nE '(^|.*:)(\s|)error:|\(failures\)|note:|warning:' "$LOG_FILE" | tail -n 80 || true
echo "---- end ----"

# 编译失败时不要立刻退出，便于 CI 仍能看到所有错误
if [ $XCB_EXIT -ne 0 ]; then
  echo "xcodebuild 编译失败 (exit=$XCB_EXIT)，请按上方错误行定位。"
  exit $XCB_EXIT
fi

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