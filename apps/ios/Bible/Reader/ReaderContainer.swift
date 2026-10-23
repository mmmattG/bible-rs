import SwiftUI
import UIKit

/// The UIKit reader in the SwiftUI app, with the Scrubber over its right edge.
struct ReaderContainer: UIViewRepresentable {
    let store: Store
    let theme: Theme
    let style: Typography
    let translation: String
    let readingLine: CGFloat
    let selection: VerseSelection?
    let marksVersion: Int
    let jump: JumpRequest?

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> ReaderHost {
        let host = ReaderHost()
        host.reader.readerDelegate = context.coordinator
        host.scrubber.delegate = context.coordinator
        context.coordinator.host = host
        return host
    }

    func updateUIView(_ host: ReaderHost, context: Context) {
        let c = context.coordinator
        let view = host.reader
        let bible = store.bible
        let translation = translation
        let options = style.options
        view.source = ChapterSource(
            content: { bible.chapter(translation: translation, index: UInt16($0), options: options) },
            marks: { bible.marks(translation: translation, chapter: UInt16($0)) })
        view.readingLine = readingLine
        view.configure(style: style, theme: theme, key: translation)
        view.selection = selection
        if c.marksVersion != marksVersion {
            c.marksVersion = marksVersion
            view.reloadMarks()
        }
        let scrubber = host.scrubber
        scrubber.readingLine = readingLine
        scrubber.configure(theme: theme)
        scrubber.isSuppressed = selection != nil
        if c.translation != translation {
            c.translation = translation
            scrubber.setAxis { bible.scrubAxis(translation: translation) }
        }
        if let jump, jump.id != c.jump {
            c.jump = jump.id
            view.jump(to: jump.chapter, verse: jump.verse, animated: jump.animated, flash: jump.flash)
            if jump.scrubbed {
                scrubber.rest(at: Position(chapter: jump.chapter, verse: jump.verse))
                scrubber.show()
            }
        }
    }

    @MainActor
    final class Coordinator: ReaderViewDelegate, ScrubberViewDelegate {
        let store: Store
        weak var host: ReaderHost?
        var marksVersion = 0
        var jump: UUID?
        var translation: String?

        init(store: Store) { self.store = store }

        func reader(_ reader: ReaderView, didReach chapter: Int, verse: Int) {
            store.reached(chapter, verse: verse)
            host?.scrubber.rest(at: Position(chapter: chapter, verse: verse))
        }

        func reader(_ reader: ReaderView, didTapVerse verse: Int, inChapter chapter: Int) {
            store.tap(verse: verse, chapter: chapter)
        }

        func reader(_ reader: ReaderView, didTapNoteOf verse: Int, inChapter chapter: Int) {
            store.selection = nil
            store.sheet = .note(store.ref(chapter: chapter, verse: verse))
        }

        func readerDidTapPage(_ reader: ReaderView) {
            store.tapPage()
        }

        func reader(_ reader: ReaderView, isReadingOn: Bool) {
            guard store.selection == nil, store.barsHidden != isReadingOn else { return }
            store.barsHidden = isReadingOn
        }

        /// Scrolling, by hand or from the status bar, shows the rail and lets go of the Scrubber's Back.
        func readerDidBeginScrolling(_ reader: ReaderView) {
            store.dismissScrubBack()
            host?.scrubber.readerDidBeginScrolling()
        }

        func readerDidEndScrolling(_ reader: ReaderView) {
            host?.scrubber.readerDidEndScrolling()
        }

        func scrubberDidBegin(_ scrubber: ScrubberView) {
            host?.reader.stopScrolling()
        }

        func scrubber(_ scrubber: ScrubberView, didScrubTo chapter: Int, verse: Int, atVerse: Bool) {
            store.scrub(to: chapter, verse: verse, atVerse: atVerse)
        }
    }
}

/// The reader, and the Scrubber over it.
final class ReaderHost: UIView {
    let reader = ReaderView()
    let scrubber = ScrubberView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(reader)
        addSubview(scrubber)
        // The Scrubber's hold sits here, over the reader, so a tap or a flick on the rail still
        // reaches the reader. A scroll that starts on the rail waits for the hold to fail, which
        // it does once the finger moves more than a few points before the hold is up.
        addGestureRecognizer(scrubber.hold)
        reader.panGestureRecognizer.require(toFail: scrubber.hold)
        scrubber.isReaderScrolling = { [weak reader] in reader.map { $0.isDragging || $0.isDecelerating } ?? false }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        reader.frame = bounds
        scrubber.frame = bounds
    }
}
