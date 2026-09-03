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

echo "==> [3/5] 无签名编译 (iphoneos, Release, arm64)"
# -scheme（而非 -target）配合 -derivedDataPath，是 Xcode 14+ 的硬规则。
# -destination 'generic/platform=iOS' 让 xcodebuild 不必连真机即可编译 Release。
# 同时关闭代码签名 + 指向越狱专用 entitlements 文件。
#
# ★ 关键修复（iOS 16 真机闪退）：CI 用的是新版 Xcode（SDK 26.x / Swift 6.x），
#   但部署目标是 iOS 16。默认情形下 Swift 运行时依赖系统自带的 libswift，
#   而 iOS 16 系统的 libswift 缺少新版编译器生成的符号 → dyld 启动即崩。
#   强制 EMBED_SWIFT_STANDARD_LIBRARIES=YES 把匹配的 Swift 运行时打进 .app/Frameworks，
#   让真机用自带的（新版、向后兼容）Swift 运行时，闪退即可消除。
# -arch arm64 + ONLY_ACTIVE_ARCH=YES 确保只产出干净的单架构设备切片。
xcodebuild \
  -project CreditCardManager.xcodeproj \
  -scheme CreditCardManager \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=YES \
  ENABLE_BITCODE=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS="CreditCardManager.jailed.entitlements" \
  EMBED_SWIFT_STANDARD_LIBRARIES=YES \
  ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES \
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
APP_NAME=$(basename "$APP_PATH")
cp -R "$APP_PATH" "Payload/$APP_NAME"

echo "    防御性清理：移除不应出现在 .app 内的杂项（避免把工程目录误当产物打包）"
rm -rf "Payload/$APP_NAME/CreditCardManager.xcodeproj"
rm -f  "Payload/$APP_NAME/build.log"
rm -f  "Payload/$APP_NAME/project.yml"
find  "Payload/$APP_NAME" -maxdepth 1 -name "*.swift"   -delete 2>/dev/null || true
find  "Payload/$APP_NAME" -maxdepth 1 -name "*.pbxproj" -delete 2>/dev/null || true

echo "    校验：Swift 运行时是否已内嵌（iOS 16 真机能否启动的关键）"
if [ -d "Payload/$APP_NAME/Frameworks" ] && [ -n "$(ls -A "Payload/$APP_NAME/Frameworks" 2>/dev/null)" ]; then
  echo "    ✅ Frameworks 目录已生成，内嵌 Swift 运行时："
  ls "Payload/$APP_NAME/Frameworks" | sed 's/^/      /'
else
  echo "    ⚠️ 警告：Frameworks 目录为空或不存在，Swift 运行时未内嵌，iOS 16 仍可能闪退！"
fi

if [ ! -d "Payload/$APP_NAME" ]; then
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
