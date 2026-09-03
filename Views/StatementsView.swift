import SwiftUI
import CoreData

struct StatementsView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var vm: StatementsViewModel
    let card: CreditCard

    @FetchRequest private var statements: FetchedResults<Statement>
    @State private var showEditor = false
    @State private var editing: Statement?

    init(card: CreditCard) {
        self.card = card
        let ctx = PersistenceController.shared.container.viewContext
        _vm = StateObject(wrappedValue: StatementsViewModel(context: ctx))

        let req = Statement.fetchRequest()
        req.predicate = NSPredicate(format: "card == %@", card)
        req.sortDescriptors = [
            NSSortDescriptor(key: "year", ascending: false),
            NSSortDescriptor(key: "month", ascending: false)
        ]
        _statements = FetchRequest(fetchRequest: req)
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("账单日 / 还款日")
                    Spacer()
                    Text("\(card.statementDay) 号 / \(card.dueDay) 号").foregroundStyle(.secondary)
                }
                HStack {
                    Text("未还合计")
                    Spacer()
                    Text(unpaidTotal.yuanString)
                        .foregroundStyle(unpaidTotal > 0 ? .red : .green)
                        .fontWeight(.semibold)
                }
            }

            ForEach(statements) { s in
                NavigationLink {
                    StatementEditorView(statement: s, card: card)
                } label: {
                    StatementRow(statement: s)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation { vm.delete(s) }
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle(card.displayName)
        .overlay {
            if statements.isEmpty {
                Text("还没有账单\n点击右上角添加")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = nil; showEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showEditor) {
            StatementEditorView(statement: nil, card: card)
        }
    }

    private var unpaidTotal: Decimal {
        statements.reduce(Decimal(0)) { $0 + $1.remaining }
    }
}

private struct StatementRow: View {
    let statement: Statement
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(statement.periodLabel).font(.headline)
                if let due = statement.dueDate {
                    Text("还款日 \(due.monthDayLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(statement.total.yuanString).font(.subheadline)
                HStack(spacing: 6) {
                    if statement.paid > 0 {
                        Text("已还 \(statement.paid.yuanString)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    StatusBadge(status: statement.effectiveStatus)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
