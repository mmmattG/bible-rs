import SwiftUI

/// How the Memory list is ordered.
enum MemorySort: String, Codable, CaseIterable, Identifiable {
    case fading, bibleOrder

    var id: Self { self }

    var label: String {
        switch self {
        case .fading: "Fading"
        case .bibleOrder: "Bible order"
        }
    }

    var order: MemoryOrder {
        switch self {
        case .fading: .fading
        case .bibleOrder: .bible
        }
    }
}

extension MemorisedPassage {
    /// "58%", or nothing before its first recall.
    var recallChanceLabel: String? {
        recallChance.map { "\(Int(($0 * 100).rounded()))%" }
    }

    /// "3:16" or "3:16–18": the reference without its book.
    var chapterAndVerses: String {
        let start = "\(first.chapter):\(first.verse)"
        return first.verse == last.verse ? start : "\(start)–\(last.verse)"
    }
}

/// The memorised passages, each with the estimated chance of recalling it now. They are listed by
/// reference alone, so the list never gives a passage away. Recall goes down the list as it is
/// ordered, from the top or from the passage tapped.
struct MemoryView: View {
    @Environment(Store.self) private var store
    let theme: Theme
    @State private var passages: [MemorisedPassage] = []

    var body: some View {
        @Bindable var store = store
        List {
            switch store.settings.memoryOrder {
            case .fading:
                ForEach(passages, id: \.first) { passage in
                    row(passage, label: passage.reference)
                }
            case .bibleOrder:
                ForEach(books, id: \.index) { book in
                    Section(book.name) {
                        ForEach(passages.filter { $0.first.book == book.index }, id: \.first) { passage in
                            row(passage, label: passage.chapterAndVerses)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if passages.isEmpty {
                ContentUnavailableView(
                    "Nothing memorised", systemImage: "rectangle.on.rectangle",
                    description: Text("Tap a verse, then Memorise."))
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Order", selection: $store.settings.memoryOrder) {
                ForEach(MemorySort.allCases) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if !passages.isEmpty {
                recallButton
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: store.settings.memoryOrder) { load() }
        .onChange(of: store.marksVersion) { load() }
    }

    private var books: [BookInfo] {
        store.bookList.filter { book in passages.contains { $0.first.book == book.index } }
    }

    private func row(_ passage: MemorisedPassage, label: String) -> some View {
        Button {
            store.startRecall(from: passage)
        } label: {
            HStack {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(theme.accent))
                Spacer()
                Text(passage.recallChanceLabel ?? "Not recalled yet")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("memory-\(passage.reference)")
        .swipeActions {
            Button(role: .destructive) {
                store.stopMemorising(passage)
            } label: {
                Label("Stop Memorising", systemImage: "trash")
            }
        }
    }

    private var recallButton: some View {
        Button {
            store.startRecall()
        } label: {
            Label("Recall", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(Color(theme.onAccent))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(theme.accent), in: Capsule())
        }
        .accessibilityIdentifier("recall")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func load() {
        passages = store.memorisedPassages(store.settings.memoryOrder)
    }
}

/// In Study: the way into the memorised passages.
struct MemoryRow: View {
    @Environment(Store.self) private var store
    let theme: Theme

    var body: some View {
        let count = store.memorisedCount
        NavigationLink {
            MemoryView(theme: theme)
        } label: {
            HStack {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(Color(theme.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(theme.ink))
                    Text(count == 1 ? "1 passage" : "\(count) passages")
                        .font(.footnote)
                        .foregroundStyle(Color(theme.ink2))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(theme.ink3))
            }
            .padding(12)
            .background(Color(theme.fill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityIdentifier("memory")
        .id(store.marksVersion)
    }
}
