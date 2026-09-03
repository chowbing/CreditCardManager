import CoreData
import CloudKit

/// Core Data + CloudKit 持久化控制器
/// 说明：本工程用「代码构建」的 NSManagedObjectModel，避免手写 .xcdatamodeld 的 XML 在 Xcode 中解析失败；
/// 同时用 NSPersistentCloudKitContainer 接入用户自有 iCloud（私有库，Apple 端到端加密）。
struct PersistenceController {
    static let shared = PersistenceController()

    static let modelName = "CreditCardManager"
    /// 改成你自己的 iCloud 容器标识（需与 entitlements、开发者后台一致）
    static let cloudKitContainerID = "iCloud.com.example.CreditCardManager"

    let container: NSPersistentContainer

    /// CloudKit 同步开关。
    /// - `false`（当前默认）：纯本地 Core Data。适用于越狱无签名 IPA、免费 Apple ID 调试、以及不需要跨设备同步的场景。
    /// - `true`：接入 CloudKit 私有库（需付费开发者账号 + 已配置 iCloud 容器 + 真机登录 iCloud）。需要多设备同步时改回此值。
    static var enableCloudKit = false

    init() {
        let model = Self.buildModel()

        let container: NSPersistentContainer
        if Self.enableCloudKit {
            let ck = NSPersistentCloudKitContainer(name: Self.modelName, managedObjectModel: model)
            container = ck
        } else {
            container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        }
        self.container = container

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("无法获取 Core Data 存储描述")
        }

        // 历史追踪 + 远程变更通知（CloudKit 同步所需，本地模式忽略远端通知即可）
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        // CloudKit 私有容器（仅开启 CloudKit 时配置）
        if Self.enableCloudKit {
            let ckOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            description.cloudKitContainerOptions = ckOptions
        }
        // 设备锁定时文件不可读（数据静态保护）
        description.setOption("NSFileProtectionComplete", forKey: NSPersistentStoreFileProtectionKey)

        container.loadPersistentStores { [weak self] _, error in
            if let error {
                // 未登录 iCloud / 未配置容器时本地存储仍可工作，仅 CloudKit 同步不可用
                print("Core Data 存储加载提示（本地仍可运行）：\(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.seedIfEmpty()
                NotificationService.shared.rescheduleAll()
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - 程序化构建数据模型

    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // ---- CreditCard ----
        let cardEntity = NSEntityDescription()
        cardEntity.name = "CreditCard"
        cardEntity.managedObjectClassName = String(describing: CreditCard.self)
        cardEntity.uniquenessConstraints = [["id"]]

        let cardAttrs: [NSAttributeDescription] = [
            attribute("id", .uuidAttributeType, optional: false),
            attribute("bankName", .stringAttributeType, optional: true),
            attribute("nickname", .stringAttributeType, optional: true),
            attribute("lastFour", .stringAttributeType, optional: true),
            attribute("statementDay", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 1)),
            attribute("dueDay", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 25)),
            attribute("creditLimit", .decimalAttributeType, optional: true),
            attribute("colorHex", .stringAttributeType, optional: true),
            attribute("order", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 0)),
            attribute("isArchived", .booleanAttributeType, optional: false, defaultValue: NSNumber(value: false)),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("updatedAt", .dateAttributeType, optional: true)
        ]
        cardEntity.properties = cardAttrs

        // ---- Statement ----
        let stmtEntity = NSEntityDescription()
        stmtEntity.name = "Statement"
        stmtEntity.managedObjectClassName = String(describing: Statement.self)
        stmtEntity.uniquenessConstraints = [["id"]]

        let stmtAttrs: [NSAttributeDescription] = [
            attribute("id", .uuidAttributeType, optional: false),
            attribute("year", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 0)),
            attribute("month", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 0)),
            attribute("statementDate", .dateAttributeType, optional: true),
            attribute("dueDate", .dateAttributeType, optional: true),
            attribute("totalAmount", .decimalAttributeType, optional: true),
            attribute("paidAmount", .decimalAttributeType, optional: true),
            attribute("isPaidInFull", .booleanAttributeType, optional: false, defaultValue: NSNumber(value: false)),
            attribute("statusRaw", .integer32AttributeType, optional: false, defaultValue: NSNumber(value: 0)),
            attribute("note", .stringAttributeType, optional: true),
            attribute("reminderOn", .booleanAttributeType, optional: false, defaultValue: NSNumber(value: true)),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("updatedAt", .dateAttributeType, optional: true)
        ]
        stmtEntity.properties = stmtAttrs

        // ---- 关系 ----
        let cardToStatements = NSRelationshipDescription()
        cardToStatements.name = "statements"
        cardToStatements.destinationEntity = stmtEntity
        cardToStatements.minCount = 0
        cardToStatements.maxCount = 0           // 0 = 多对
        cardToStatements.deleteRule = .cascadeDeleteRule
        cardToStatements.isOrdered = false

        let stmtToCard = NSRelationshipDescription()
        stmtToCard.name = "card"
        stmtToCard.destinationEntity = cardEntity
        stmtToCard.minCount = 0
        stmtToCard.maxCount = 1                 // 一对一
        stmtToCard.deleteRule = .nullifyDeleteRule

        cardToStatements.inverseRelationship = stmtToCard
        stmtToCard.inverseRelationship = cardToStatements

        cardEntity.properties.append(cardToStatements)
        stmtEntity.properties.append(stmtToCard)

        model.entities = [cardEntity, stmtEntity]
        return model
    }

    private static func attribute(_ name: String,
                                  _ type: NSAttributeType,
                                  optional: Bool,
                                  defaultValue: Any? = nil) -> NSAttributeDescription {
        let a = NSAttributeDescription()
        a.name = name
        a.attributeType = type
        a.isOptional = optional
        if let dv = defaultValue { a.defaultValue = dv }
        return a
    }

    // MARK: - 首次启动示例数据
    private func seedIfEmpty() {
        let ctx = container.viewContext
        let count = (try? ctx.count(for: CreditCard.fetchRequest())) ?? 0
        guard count == 0 else { return }

        let cardsVM = CardsViewModel(context: ctx)
        let today = Date()
        let y = Calendar.current.component(.year, from: today)
        let m = Calendar.current.component(.month, from: today)

        let card = cardsVM.addCard(
            bank: "招商银行", nickname: "日常消费卡", lastFour: "8888",
            statementDay: 5, dueDay: 23, creditLimit: Decimal(string: "50000"), colorHex: CardPalette.colors[0]
        )

        let stmtsVM = StatementsViewModel(context: ctx)
        let sd = DateCycleHelper.statementDate(year: y, month: m, statementDay: 5)
        let dd = DateCycleHelper.dueDate(year: y, month: m, statementDay: 5, dueDay: 23)
        stmtsVM.addStatement(card: card, year: y, month: m,
                             statementDate: sd, dueDate: dd,
                             total: Decimal(string: "3280.50")!, paid: Decimal(0),
                             note: "示例账单（可删除）", reminderOn: true)

        // 上个月的账单（已还清）
        let prev = Calendar.current.date(byAdding: .month, value: -1, to: today)!
        let py = Calendar.current.component(.year, from: prev)
        let pm = Calendar.current.component(.month, from: prev)
        let psd = DateCycleHelper.statementDate(year: py, month: pm, statementDay: 5)
        let pdd = DateCycleHelper.dueDate(year: py, month: pm, statementDay: 5, dueDay: 23)
        stmtsVM.addStatement(card: card, year: py, month: pm,
                             statementDate: psd, dueDate: pdd,
                             total: Decimal(string: "5120.00")!, paid: Decimal(string: "5120.00")!,
                             note: "已还清示例", reminderOn: true)
    }

    // MARK: - 工具
    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() }
        catch { print("保存失败：\(error.localizedDescription)") }
    }

    /// 清空所有数据（卡片 + 账单）
    func clearAll() {
        let ctx = container.viewContext
        let sReq = NSFetchRequest<NSFetchRequestResult>(entityName: "Statement")
        let cReq = NSFetchRequest<NSFetchRequestResult>(entityName: "CreditCard")
        let sBatch = NSBatchDeleteRequest(fetchRequest: sReq)
        let cBatch = NSBatchDeleteRequest(fetchRequest: cReq)
        _ = try? ctx.execute(sBatch)
        _ = try? ctx.execute(cBatch)
        ctx.reset()
    }
}
