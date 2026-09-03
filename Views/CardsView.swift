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

    init() {
        let ctx = PersistenceController.shared.container.viewContext
        _vm = StateObject(wrappedValue: CardsViewModel(context: ctx))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(cards) { card in
                    NavigationLink {
                        StatementsView(card: card)
                    } label: {
                        CardRow(card: card)
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
        }
    }
}

private struct CardRow: View {
    let card: CreditCard
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(card.themeColor)
                .frame(width: 10)
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
