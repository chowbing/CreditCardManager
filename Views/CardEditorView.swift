import SwiftUI

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @StateObject private var vm: CardsViewModel

    let card: CreditCard?

    @State private var bankName: String
    @State private var nickname: String
    @State private var lastFour: String
    @State private var statementDay: Int
    @State private var dueDay: Int
    @State private var creditLimitText: String
    @State private var selectedColor: String

    @State private var showError = false

    private let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()

    init(card: CreditCard?) {
        self.card = card
        let ctx = PersistenceController.shared.container.viewContext
        _vm = StateObject(wrappedValue: CardsViewModel(context: ctx))

        _bankName = State(initialValue: card?.bankName ?? "")
        _nickname = State(initialValue: card?.nickname ?? "")
        _lastFour = State(initialValue: card?.lastFour ?? "")
        _statementDay = State(initialValue: Int(card?.statementDay ?? 1))
        _dueDay = State(initialValue: Int(card?.dueDay ?? 25))
        if let limit = card?.creditLimit {
            _creditLimitText = State(initialValue: decimalFormatter.string(from: limit) ?? "")
        } else {
            _creditLimitText = State(initialValue: "")
        }
        _selectedColor = State(initialValue: card?.colorHex ?? CardPalette.colors[0])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("发卡行（如 招商银行）", text: $bankName)
                    TextField("卡片昵称（如 日常消费卡）", text: $nickname)
                    TextField("卡号后四位", text: $lastFour)
                        .keyboardType(.numberPad)
                        .onChange(of: lastFour) { newValue in
                            lastFour = String(newValue.prefix(4).filter { $0.isNumber })
                        }
                }

                Section("账期") {
                    Picker("账单日", selection: $statementDay) {
                        ForEach(1...28, id: \.self) { d in
                            Text("\(d) 号").tag(d)
                        }
                    }
                    Picker("还款日", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { d in
                            Text("\(d) 号").tag(d)
                        }
                    }
                }

                Section("额度与外观") {
                    TextField("授信额度（可选）", text: $creditLimitText)
                        .keyboardType(.decimalPad)
                    CardColorPicker(selected: $selectedColor)
                }
            }
            .navigationTitle(card == nil ? "添加卡片" : "编辑卡片")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .alert("请填写发卡行", isPresented: $showError) {
                Button("好") {}
            }
        }
    }

    private func save() {
        guard !bankName.trimmingCharacters(in: .whitespaces).isEmpty else {
            showError = true
            return
        }
        let limit = decimalFormatter.number(from: creditLimitText)?.decimalValue

        if let card {
            vm.update(card, bank: bankName, nickname: nickname, lastFour: lastFour.isEmpty ? nil : lastFour,
                      statementDay: statementDay, dueDay: dueDay, creditLimit: limit, colorHex: selectedColor)
        } else {
            vm.addCard(bank: bankName, nickname: nickname, lastFour: lastFour.isEmpty ? nil : lastFour,
                       statementDay: statementDay, dueDay: dueDay, creditLimit: limit, colorHex: selectedColor)
        }
        dismiss()
    }
}
