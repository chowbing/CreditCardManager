# 信用卡账单管理（iOS 16+）

一款面向个人的 iOS 信用卡账单管理 App：手动录入多张信用卡的每月账单，记录账单日 / 还款日 / 金额 / 已还情况，按年、按月、按卡多维度统计分析，并支持本地推送提醒与逾期提示。数据本地持久化，并通过 CloudKit 私有库加密同步到用户自有 iCloud。

> 本工程由代码生成（XcodeGen），无需手动创建 `.xcodeproj`。

## 技术栈
- SwiftUI + Swift Charts（iOS 16 可用）
- Core Data（`NSPersistentCloudKitContainer`）本地存储 + CloudKit 私有库同步
- `UNUserNotificationCenter` 本地通知（临近还款 / 逾期提醒）
- `LocalAuthentication` 应用锁（Face ID / Touch ID / 设备密码兜底）
- 零第三方依赖（所有框架均为系统框架）

## 目录结构
```
CreditCardManager/
├── project.yml                      # XcodeGen 工程描述
├── CreditCardManager.entitlements  # iCloud + CloudKit 能力
├── CreditCardManagerApp.swift      # @main 入口
├── RootView.swift                  # Tab 导航 + 应用锁覆盖层
├── Models/                         # Core Data 实体扩展 + 枚举 + 颜色工具
├── Data/                           # 持久化容器（程序化模型）+ 统计引擎
├── Services/                       # 日期账期 / 通知 / 安全
├── ViewModels/                     # 卡片 / 账单 / 统计视图模型
└── Views/                          # 概览 / 卡片 / 账单 / 统计 / 设置 / 锁屏
```

## 构建与运行
```bash
# 1. 安装 XcodeGen（一次性）
brew install xcodegen

# 2. 生成工程
cd CreditCardManager
xcodegen generate

# 3. 打开
open CreditCardManager.xcodeproj
```

### 必须修改的两处
1. **Bundle ID**：把 `project.yml` 中的 `com.example.CreditCardManager` 改成你自己的（如 `com.yourorg.CreditCardManager`），并填入 `DEVELOPMENT_TEAM`（开发者团队 ID）。
2. **CloudKit 容器**：
   - 在 `Persistence.swift` 中修改 `cloudKitContainerID`（与下面一致）；
   - 在 `CreditCardManager.entitlements` 与开发者后台创建对应的 iCloud 容器 `iCloud.com.yourorg.CreditCardManager`；
   - Xcode → Signing & Capabilities → 勾选 iCloud → CloudKit → 选择该容器。

> 仅本地使用：模拟器即可运行（Core Data 本地存储）。CloudKit 多设备同步需在**真机 + 已登录 iCloud + 开发者账号**下开启容器能力。免费 Apple ID 可开发调试，上架需付费开发者。

## 免费 Apple ID 真机调试（路径 4）

适合「不想付费、只想在自己的 iPhone 上把这个 App 跑起来」的场景。**前提认知**：免费账号只能 Xcode 直连真机 Run，**产不出可分发/可安装的正式 IPA**，App 7 天过期后需重签，且不能发给他人安装。要做正式 IPA 分发，请走 CloudKit/付费打包路径。

### 必做的两处工程调整（绕过 CloudKit 能力限制）
1. **关闭 CloudKit**：把 `Persistence.swift` 中的
   ```swift
   static var enableCloudKit = true
   ```
   改为 `false`。这样使用纯本地 Core Data，个人团队不支持 iCloud 能力，不关会导致签名/运行直接失败。
2. **去掉 iCloud 能力**：Xcode 打开工程后，进入 `Signing & Capabilities`，选中 **iCloud** 这一项，点左下角 `-` 移除（或临时把 `CreditCardManager.entitlements` 里的 iCloud 相关键值删掉）。否则 Xcode 会报错 `Your app contains unsupported capabilities`。

### Xcode 操作步骤
1. Xcode → `Settings` → `Accounts` → 用你的**免费 Apple ID** 登录（无需付费）。
2. 工程 `TARGETS` → `Signing & Capabilities` → `Team` 选自动生成的 **你的名字 (Personal Team)**；勾选 `Automatically manage signing`；Bundle ID 用你自己的反向域名（如 `com.yourname.CreditCardManager`，不能与 App Store 已存在冲突）。
3. iPhone 连 USB，顶部 Scheme 设备选你的 iPhone，`⌘R` 运行。
4. 首次运行需在 iPhone：`设置 → 通用 → VPN与设备管理 → 信任“你的 Apple ID”`。
5. 之后每隔 7 天 Xcode 重新 `⌘R` 一次即可自动重签。

> 本地通知（逾期/还款提醒）在免费账号下**正常可用**（仅需 `UNUserNotificationCenter` 授权，不需要 iCloud 能力）。数据仅存本机，无跨设备同步。

## 核心数据模型
- **CreditCard（信用卡）**：bankName、nickname、lastFour、statementDay、dueDay、creditLimit、colorHex、isArchived 等。
- **Statement（每月账单）**：year、month、statementDate、dueDate、totalAmount、paidAmount、isPaidInFull、note、reminderOn 等；状态（未还 / 部分还 / 已还清 / 逾期）按「已还金额 + 还款日」实时推导。
- 金额统一使用 `Decimal`（底层 `NSDecimalNumber`），避免浮点误差。

## 统计维度
- 按月 / 按年 / 按卡：每月总支出、已还 vs 未还、完成率。
- 逾期：逾期笔数与逾期金额。

## 已知边界
- 当前环境为 Windows，源码未经本地编译，请在你本地 Xcode 中按上述步骤验证。
- 未实现：多币种、消费分类标签、OCR 识别、第三方记账导入（数据模型已预留扩展位）。
- 本地通知需用户授权；系统可能在勿扰 / 低电量时延迟，逾期兜底以 App 内红点 / 列表为准。

## 越狱设备：生成无签名 IPA（无需 Apple 账号 / 证书）

越狱设备可安装「无签名 IPA」，因此打包环节**不需要开发者账号、证书、Provisioning Profile**。注意：**编译仍需 macOS + Xcode 工具链**，本工程在 Windows 下只能提供源码与打包脚本，无法在此直接产出 IPA。

### 前置（一次性）
- 把 `Persistence.swift` 中的 `static var enableCloudKit = true` 改为 `false`：越狱无签名环境下 CloudKit 同步不可用，纯本地 Core Data 即可满足记账需求，且避免 iCloud 能力带来的编译/运行干扰。
- （已提供）`CreditCardManager.jailed.entitlements`：去除了 iCloud 能力，供无签名打包使用。

### 方式 A：GitHub Actions 云端自动打包（推荐，无需本地 Mac）
1. 把本工程推到 GitHub 仓库（`.xcodeproj` 已被 `.gitignore` 忽略，靠 `xcodegen generate` 重建）。
2. 仓库 `Actions` 页启用 Workflow；push 到 `main` 或手动 `Run workflow`。
3. 运行完成后在 `Artifacts` 下载 `CreditCardManager-IPA`（即 `CreditCardManager.ipa`）。
4. 用越狱安装工具（AppSync Unified / Sideloadly / Filza 等）装入设备。

> GitHub 公开仓库的 macOS 运行额度免费；私有仓库有月度额度限制（以 GitHub 当前政策为准）。

### 方式 B：本地 Mac 打包
```bash
cd CreditCardManager
chmod +x build-jailed.sh
./build-jailed.sh          # 产出当前目录的 CreditCardManager.ipa
```
脚本流程：`xcodegen generate` → 无签名 `xcodebuild` → 打包 `Payload/*.app` 为 IPA。

### 边界
- 无签名 IPA **不能**在非越狱设备上安装；必须越狱 + 安装工具。
- CloudKit 多设备同步在此模式下不可用（需付费账号 + 已授权容器）。
- 若安装时报 entitlements 相关错误，可用 `ldid` 伪签名或改用 AltStore / Sideloadly 以免费 Apple ID 自签。

