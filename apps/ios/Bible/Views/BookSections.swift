import SwiftUI

/// The books by section of the canon: the sections under their testaments, the open section's
/// books folded out beneath it, and the chosen book's chapters straight beneath the book, so a
/// chapter is chosen where the book was. It opens on the book being read, so its chapters are one
/// tap away and any chapter at most three. Another section opens to its books alone, so none of
/// them is pushed down behind chapters nobody asked for.
struct BookSections: View {
    @Environment(Store.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let theme: Theme
    let go: (Int) -> Void

    /// The book whose chapters show; `nil` is the book being read.
    @State private var chosen: UInt8?
    @State private var browsing = Browsing.chosenBook
    /// What to bring into view next, and how many times that's been asked, so choosing the
    /// book already chosen scrolls to it again.
    @State private var reveal = Reveal.current
    @State private var reveals = 0
    /// Compact rows, as in a sidebar.
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .footnote) private var headerHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .subheadline) private var bookIndent: CGFloat = 12

    /// Which section has its books unfolded.
    private enum Browsing: Equatable {
        /// The chosen book's, as when the picker opens.
        case chosenBook
        case section(String)
        case none
    }

    private enum Reveal {
        /// The chapter being read.
        case current
        /// A section just opened.
        case books
        /// The chapters of a book just chosen.
        case chapters
    }

    /// Where a book just chosen settles: high enough that its chapters show beneath it.
    private static let chosenBookAnchor = UnitPoint(x: 0.5, y: 0.25)

    private var current: BookInfo { store.book(of: store.position.chapter) }
    private var book: BookInfo { chosen.map { store.bookList[Int($0)] } ?? current }
    private var openSection: String? {
        switch browsing {
        case .chosenBook: store.section(of: book).name
        case .section(let name): name
        case .none: nil
        }
    }
    /// One column of sections rather than a column per testament, at the largest text sizes.
    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                browse.padding(.bottom, 16)
            }
            .task(id: reveals) {
                // Once the new books and chapters are laid out.
                await Task.yield()
                switch reveal {
                case .current:
                    proxy.scrollTo(Self.id(book), anchor: .center)
                    proxy.scrollTo(ChapterGrid.id(store.position.chapter), anchor: .center)
                case .books:
                    if let openSection {
                        withAnimation { proxy.scrollTo(Self.sectionID(openSection), anchor: .top) }
                    }
                case .chapters:
                    withAnimation { proxy.scrollTo(Self.id(book), anchor: Self.chosenBookAnchor) }
                }
            }
        }
    }

    /// Each testament's sections, the open one with its books beneath it, and the chosen book
    /// with its chapters.
    private var browse: some View {
        let layout =
            stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout {
            testament("Old Testament", store.sections.filter { !$0.newTestament })
            testament("New Testament", store.sections.filter(\.newTestament))
        }
        .padding(.horizontal, 10)
    }

    private func testament(_ title: String, _ sections: [BibleSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(title)
            ForEach(sections, id: \.name) { s in
                sectionRow(s)
                if s.name == openSection {
                    ForEach(store.bookList.filter { s.contains($0) }, id: \.index) { b in
                        bookRow(b)
                        if b.index == book.index && b.chapters > 1 {
                            // Three across in a testament's column on a phone.
                            ChapterGrid(
                                book: b, reading: store.position.chapter, theme: theme, go: go, cell: 40, spacing: 6
                            )
                            .padding(.leading, bookIndent)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // VoiceOver reads down one testament, then the other.
        .accessibilityElement(children: .contain)
    }

    /// A section's row, which folds its books in and out: the open one is bold, and the one
    /// holding the chapter being read is in the accent.
    private func sectionRow(_ s: BibleSection) -> some View {
        let open = s.name == openSection
        let reading = s.contains(current)
        let state = open ? "Expanded" : "Collapsed"
        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                if open {
                    browsing = .none
                } else {
                    browsing = .section(s.name)
                    show(.books)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(s.name)
                    .font(.subheadline.weight(open ? .semibold : reading ? .medium : .regular))
                    .foregroundStyle(reading ? Color(theme.accent) : Color(theme.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(theme.ink3))
                    .rotationEffect(.degrees(open ? 0 : -90))
                    // The value says whether it's open.
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(Self.sectionID(s.name))
        .accessibilityValue(reading ? "\(state), has the chapter you're reading" : state)
        .accessibilityHint(open ? "Folds its books away" : "Shows its books")
    }

    /// A book under its section: the chosen one sits on the soft accent, as the Mac sidebar's
    /// selected rows do, and the one being read is in the accent.
    private func bookRow(_ b: BookInfo) -> some View {
        let selected = b.index == book.index
        let reading = b.index == current.index
        return Button {
            if b.chapters == 1 {
                go(Int(b.firstChapter))
            } else {
                withAnimation(.smooth(duration: 0.25)) {
                    chosen = b.index
                    show(.chapters)
                }
            }
        } label: {
            Text(b.name)
                .font(.subheadline.weight(selected ? .semibold : reading ? .medium : .regular))
                .foregroundStyle(selected || reading ? Color(theme.accent) : Color(theme.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .background(
                    selected ? Color(theme.accentSoft) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, bookIndent)
        .id(Self.id(b))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(reading ? "Book you're reading" : "")
        .accessibilityHint(b.chapters == 1 ? "Opens the book" : "Shows its chapters")
    }

    /// Brings `what` into view once it is laid out.
    private func show(_ what: Reveal) {
        reveal = what
        reveals += 1
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(theme.ink3))
            .padding(.horizontal, 10)
            .frame(minHeight: headerHeight, alignment: .bottomLeading)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// The scroll ids of a section's row and a book's row.
    private static func sectionID(_ name: String) -> String { "section-\(name)" }
    private static func id(_ book: BookInfo) -> String { "book-\(book.index)" }
}
