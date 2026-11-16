import SwiftUI

/// The books by section of the canon: the sections under their testaments, the open section's
/// books folded out beneath it, and the chosen book's chapters straight beneath the book across
/// the full width, so a chapter is chosen where the book was. It opens on the book being read, so
/// its chapters are one tap away and any chapter at most three. Another section opens to its books
/// alone, so none of them is pushed down behind chapters nobody asked for.
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
        SpannedColumns(columns: stacked ? 1 : 2, spacing: 2) {
            testament("Old Testament", store.sections.filter { !$0.newTestament }, column: 0)
            testament("New Testament", store.sections.filter(\.newTestament), column: stacked ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func testament(_ title: String, _ sections: [BibleSection], column: Int) -> some View {
        header(title).row(column: column)
        ForEach(sections, id: \.name) { s in
            sectionRow(s).row(column: column)
            if s.name == openSection {
                ForEach(store.bookList.filter { s.contains($0) }, id: \.index) { b in
                    bookRow(b).row(column: column)
                    if b.index == book.index && b.chapters > 1 {
                        ChapterGrid(book: b, reading: store.position.chapter, theme: theme, go: go)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .row(column: column, spansColumns: true)
                    }
                }
            }
        }
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

/// Rows in equal columns, each filling downwards. A row that spans the columns sits beneath the
/// rows before it in its own column, and pushes down the other columns' rows that would cross it.
private struct SpannedColumns: Layout {
    let columns: Int
    let spacing: CGFloat

    struct Column: LayoutValueKey {
        static let defaultValue = 0
    }

    struct SpansColumns: LayoutValueKey {
        static let defaultValue = false
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columnWidth = width / CGFloat(columns)
        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var span: CGRect?
        // The spanning row's own column first, so the other columns know where it is.
        let spanColumn = subviews.first { $0[SpansColumns.self] }?[Column.self]
        let order = [spanColumn].compactMap { $0 } + (0..<columns).filter { $0 != spanColumn }
        for column in order {
            var y: CGFloat = 0
            for (index, subview) in subviews.enumerated() where subview[Column.self] == column {
                let spans = subview[SpansColumns.self]
                let rowWidth = spans ? width : columnWidth
                let height = subview.sizeThatFits(ProposedViewSize(width: rowWidth, height: nil)).height
                if let span, y < span.maxY, y + height > span.minY {
                    y = span.maxY + spacing
                }
                frames[index] = CGRect(x: spans ? 0 : CGFloat(column) * columnWidth, y: y, width: rowWidth, height: height)
                if spans { span = frames[index] }
                y += height + spacing
            }
        }
        return frames
    }
}

extension View {
    /// Where a row goes in `SpannedColumns`. VoiceOver reads down one column, then the next.
    fileprivate func row(column: Int, spansColumns: Bool = false) -> some View {
        layoutValue(key: SpannedColumns.Column.self, value: column)
            .layoutValue(key: SpannedColumns.SpansColumns.self, value: spansColumns)
            .accessibilitySortPriority(Double(-column))
    }
}
