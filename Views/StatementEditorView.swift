import SwiftUI

struct StatementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: StatementsViewModel

    let statement: Statement?
    let card: CreditCard

    @State private var year: Int
    @State private var month: Int
    @State private var statementDate: Date
    @State private var dueDate: Date
    @State private var totalText: String
    @State private var paidText: String
    @State private var note: String
    @State private var reminderOn: Bool
    @State private var showError = false

    private let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()

    private let years: [Int]

    init(statement: Statement? = nil, card: CreditCard, preferredYear: Int? = nil, preferredMonth: Int? = nil) {
        self.statement = statement
        self.card = card
        let ctx = PersistenceController.shared.container.viewContext
        _vm = StateObject(wrappedValue: StatementsViewModel(context: ctx))

        let now = Date()
        let cy = Calendar.current.component(.year, from: now)
        let cm = Calendar.current.component(.month, from: now)
        years = Array((cy - 2)...(cy + 1))

        if let s = statement {
            _year = State(initialValue: Int(s.year))
            _month = State(initialValue: Int(s.month))
            _statementDate = State(initialValue: s.statementDate ?? now)
            _dueDate = State(initialValue: s.dueDate ?? now)
            _totalText = State(initialValue: decimalFormatter.string(from: s.totalAmount ?? NSDecimalNumber(0)) ?? "")
            _paidText = State(initialValue: decimalFormatter.string(from: s.paidAmount ?? NSDecimalNumber(0)) ?? "")
            _note = State(initialValue: s.note ?? "")
            _reminderOn = State(initialValue: s.reminderOn)
        } else {
            // 新建账单：默认归属「当前真实月份」；若调用方指定了 preferred 年月
            //（如首页便捷录入「当前展示账期」），则以指定年月为归属，确保跳月后
            // 点卡片直接落在正确的下一期。
            let y = preferredYear ?? cy
            let m = preferredMonth ?? cm
            _year = State(initialValue: y)
            _month = State(initialValue: m)
            _statementDate = State(initialValue: DateCycleHelper.statementDate(year: y, month: m, statementDay: Int(card.statementDay)))
            _dueDate = State(initialValue: DateCycleHelper.dueDate(year: y, month: m, dueDay: Int(card.dueDay)))
            _totalText = State(initialValue: "")
            _paidText = State(initialValue: "")
            _note = State(initialValue: "")
            _reminderOn = State(initialValue: true)
        }
    }

    /// 便捷入口：直接针对某个账期（year/month）打开编辑器。
    /// 若该期已有账单则编辑它；否则以该期为归属新建一笔。
    init(card: CreditCard, year: Int, month: Int) {
        let existing = card.statement(year: year, month: month)
        self.init(statement: existing, card: card, preferredYear: year, preferredMonth: month)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("年份", selection: $year) {
                        ForEach(years, id: \.self) { y in
                            Text("\(y) 年").tag(y)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("月份", selection: $month) {
                        ForEach(1...12, id: \.self) { m in
                            Text("\(m) 月").tag(m)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("当前所属期")
                        Spacer()
                        Text("\(year) 年 \(month) 月")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("账单所属期")
                } footer: {
                    Text("所属期 = 这笔账单归到哪个月。例如 9 月 5 日出账、9 月 23 日还款，都算 9 月。点上面「年份 / 月份」两行即可修改。")
                }

                Section("关键日期") {
                    DatePicker("账单日", selection: $statementDate, displayedComponents: .date)
                    DatePicker("还款日", selection: $dueDate, displayedComponents: .date)
                }

                Section("金额") {
                    TextField("账单金额", text: $totalText)
                        .keyboardType(.decimalPad)
                    TextField("已还款金额", text: $paidText)
                        .keyboardType(.decimalPad)
                    Button("标记为已还清") {
                        paidText = totalText
                    }
                    .disabled(totalText.isEmpty)
                }

                Section("其他") {
                    TextField("备注（可选）", text: $note)
                    Toggle("开启还款提醒", isOn: $reminderOn)
                }
            }
            .navigationTitle(statement == nil ? "添加账单" : "编辑账单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("请填写账单金额", isPresented: $showError) {
                Button("好") {}
            }
        }
    }

    private func save() {
        guard let total = decimalFormatter.number(from: totalText)?.decimalValue, total >= 0 else {
            showError = true
            return
        }
        let paid = decimalFormatter.number(from: paidText)?.decimalValue ?? 0

        if let s = statement {
            vm.update(s, statementDate: statementDate, dueDate: dueDate,
                      total: total, paid: paid, note: note.isEmpty ? nil : note, reminderOn: reminderOn)
        } else {
            vm.addStatement(card: card, year: year, month: month,
                            statementDate: statementDate, dueDate: dueDate,
                            total: total, paid: paid, note: note.isEmpty ? nil : note, reminderOn: reminderOn)
        }
        dismiss()
    }
}
