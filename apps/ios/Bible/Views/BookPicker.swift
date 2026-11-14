import SwiftUI

/// How the book picker lists the books: all 66 under their testaments, or by section of the canon.
enum BookLayout: String, Codable, CaseIterable, Identifiable {
    case allBooks, sections

    var id: Self { self }

    var label: String {
        switch self {
        case .allBooks: "All books"
        case .sections: "Sections"
        }
    }
}

extension BibleSection {
    func contains(_ book: BookInfo) -> Bool { (firstBook...lastBook).contains(book.index) }
}

/// Books and chapters, and a field that takes a reference: "jn 3:16", "ps 23", "1 cor 13".
struct BookPicker: View {
    @Environment(Store.self) private var store
    let theme: Theme
    let close: () -> Void
    @State private var query = ""
    @State private var open: UInt8?
    @AccessibilityFocusState private var closeFocused: Bool

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestions
                } else if store.settings.bookLayout == .sections {
                    BookSections(theme: theme, go: go(chapter:))
                } else {
                    allBooks
                }
            }
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Go to… (jn 3:16)"
            )
            .scrollContentBackground(.hidden)
            .background(Color(theme.paper))
            .toolbarBackground(Color(theme.paper), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(theme.colorScheme, for: .navigationBar)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(of: .search) {
                if let reference = parseReference(input: query) ?? suggestReferences(input: query, limit: 1).first {
                    go(reference)
                }
            }
            .navigationTitle("Books")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $store.settings.bookLayout) {
                            ForEach(BookLayout.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(store.settings.bookLayout.label)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .accessibilityLabel("Show books by")
                    .accessibilityValue(store.settings.bookLayout.label)
                    .accessibilityIdentifier("book-layout")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                        .accessibilityIdentifier("close-books")
                        .accessibilityFocused($closeFocused)
                        .onAppear { closeFocused = store.booksOpen }
                        .onChange(of: store.booksOpen) { _, open in closeFocused = open }
                }
            }
        }
    }

    private var suggestions: some View {
        List {
            let suggestions = suggestReferences(input: query, limit: 8)
            if suggestions.isEmpty {
                Text("No book matches “\(query)”")
                    .foregroundStyle(Color(theme.ink2))
                    .listRowBackground(Color(theme.surface))
            }
            ForEach(suggestions, id: \.label) { reference in
                Button {
                    go(reference)
                } label: {
                    Label(reference.label, systemImage: reference.verse == nil ? "book" : "text.quote")
                        .foregroundStyle(Color(theme.ink))
                }
                .listRowBackground(Color(theme.surface))
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Every book under its testament; a book opens its chapters in place.
    private var allBooks: some View {
        ScrollViewReader { proxy in
            List {
                testament("Old Testament", store.bookList.filter { !$0.newTestament })
                testament("New Testament", store.bookList.filter(\.newTestament))
            }
            .listStyle(.insetGrouped)
            .onAppear {
                let book = store.book(of: store.position.chapter).index
                open = book
                proxy.scrollTo(book, anchor: .center)
            }
        }
    }

    private func testament(_ title: String, _ books: [BookInfo]) -> some View {
        Section {
            ForEach(books, id: \.index) { book in
                row(book)
                    .id(book.index)
                    .listRowBackground(Color(theme.surface))
            }
        } header: {
            Text(title).foregroundStyle(Color(theme.ink2))
        }
    }

    @ViewBuilder
    private func row(_ book: BookInfo) -> some View {
        let current = store.book(of: store.position.chapter).index == book.index
        Button {
            if book.chapters == 1 {
                go(chapter: Int(book.firstChapter))
            } else {
                withAnimation(.smooth(duration: 0.25)) { open = open == book.index ? nil : book.index }
            }
        } label: {
            HStack {
                Text(book.name)
                    .font(.body.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? Color(theme.accent) : Color(theme.ink))
                Spacer()
                Text(book.chapters == 1 ? "1 chapter" : "\(book.chapters)")
                    .font(.subheadline)
                    .foregroundStyle(Color(theme.ink2))
                if book.chapters > 1 {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(theme.ink3))
                        .rotationEffect(.degrees(open == book.index ? 0 : -90))
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityHint(book.chapters == 1 ? "Opens the book" : "Shows its chapters")
        if open == book.index && book.chapters > 1 {
            ChapterGrid(book: book, reading: store.position.chapter, theme: theme, go: go(chapter:))
                .padding(.vertical, 6)
        }
    }

    private func go(chapter: Int) {
        store.go(to: chapter)
        close()
    }

    private func go(_ reference: Reference) {
        store.go(to: reference)
        close()
    }
}

/// A book's chapters as numbered cells; the chapter being read is filled with the accent.
struct ChapterGrid: View {
    let book: BookInfo
    /// The chapter being read, in the canonical grid.
    let reading: Int
    let theme: Theme
    let go: (Int) -> Void
    /// The narrowest a cell may be, and the gap between cells.
    var cell: CGFloat = 48
    var spacing: CGFloat = 8

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: spacing)], spacing: spacing) {
            ForEach(1...Int(book.chapters), id: \.self) { n in
                let index = Int(book.firstChapter) + n - 1
                let current = index == reading
                Button {
                    go(index)
                } label: {
                    Text("\(n)")
                        .font(.body.monospacedDigit().weight(current ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(current ? Color(theme.onAccent) : Color(theme.ink))
                        .background(
                            current ? Color(theme.accent) : Color(theme.fill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(book.name) \(n)")
                .accessibilityAddTraits(current ? .isSelected : [])
                .id(Self.id(index))
            }
        }
    }

    /// The scroll id of a chapter's cell.
    static func id(_ chapter: Int) -> String { "chapter-\(chapter)" }
}
