import SwiftUI
import CoreData

struct CardsView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var vm: CardsViewModel
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "order", ascending: true)],
        predicate: NSPredicate(format: "isArchived == %@", NSNumber(value: false))
    )
    private var cards: FetchedResults<CreditCard>

    @State private var showEditor = false
    @State private var editingCard: CreditCard?
    /// 正在快速改色的卡片（非空则弹出颜色面板）
    @State private var colorTarget: CreditCard?

    init() {
        let ctx = PersistenceController.shared.container.viewContext
        _vm = StateObject(wrappedValue: CardsViewModel(context: ctx))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(cards) { card in
                    HStack(spacing: 12) {
                        // 色块按钮与导航链接同级（而非嵌在链接内部），
                        // 避免 List 行内 Button 与 NavigationLink 争抢点击。
                        CardColorChip(hex: card.colorHex ?? CardPalette.colors[0]) {
                            colorTarget = card
                        }

                        NavigationLink {
                            StatementsView(card: card)
                        } label: {
                            CardRow(card: card)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingCard = card
                            showEditor = true
                        } label: { Label("编辑", systemImage: "pencil") }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation { vm.delete(card) }
                        } label: { Label("删除", systemImage: "trash") }

                        Button {
                            vm.setArchived(card, archived: true)
                        } label: { Label("归档", systemImage: "archivebox") }
                        .tint(.orange)
                    }
                }
            }
            .navigationTitle("我的信用卡")
            .overlay {
                if cards.isEmpty {
                    EmptyState(text: "还没有卡片\n点击右上角添加第一张信用卡")
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingCard = nil
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showEditor) {
                CardEditorView(card: editingCard)
            }
            .sheet(item: $colorTarget) { card in
                CardColorSheet(card: card, vm: vm)
            }
        }
    }
}

// MARK: - 快速改色面板（从列表色块进入）
private struct CardColorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: CreditCard
    let vm: CardsViewModel
    @State private var selected: String

    init(card: CreditCard, vm: CardsViewModel) {
        self.card = card
        self.vm = vm
        _selected = State(initialValue: card.colorHex ?? CardPalette.colors[0])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                // 实时预览：改色即时反映在这张卡的样子上
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: selected))
                    .frame(height: 84)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.displayName)
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            if let last4 = card.lastFour, !last4.isEmpty {
                                Text("•••• \(last4)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.horizontal, 16)

                CardColorPicker(selected: $selected)
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .navigationTitle("卡片颜色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        vm.setColor(card, colorHex: selected)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct CardRow: View {
    let card: CreditCard
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.displayName).font(.headline)
                if let bank = card.bankName, !bank.isEmpty {
                    Text(bank).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text("账单日 \(card.statementDay) 号")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("还款日 \(card.dueDay) 号")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let last4 = card.lastFour, !last4.isEmpty {
                Text("•••• \(last4)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EmptyState: View {
    let text: String
    var body: some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding()
    }
}
