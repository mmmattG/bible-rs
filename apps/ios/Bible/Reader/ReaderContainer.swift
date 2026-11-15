import SwiftUI
import UIKit

/// The UIKit reader in the SwiftUI app.
struct ReaderContainer: UIViewRepresentable {
    let store: Store
    let theme: Theme
    let style: Typography
    let translation: String
    let readingLine: CGFloat
    let selection: VerseSelection?
    let marksVersion: Int
    let jump: JumpRequest?
    let recall: RecallRun?
    let recallLetters: Bool
    let onBooksPan: (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.readerDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        let c = context.coordinator
        c.onBooksPan = onBooksPan
        // Recalling, a sideways drag reveals the passage instead.
        view.booksGestureEnabled = store.sheet == nil && !store.booksOpen && store.recall == nil
        if store.booksOpen && view.isScrollEnabled {
            view.setContentOffset(view.contentOffset, animated: false)
        }
        view.isScrollEnabled = !store.booksOpen
        view.accessibilityElementsHidden = store.booksOpen
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
        if let jump, jump.id != c.jump {
            c.jump = jump.id
            view.jump(to: jump.chapter, verse: jump.verse, animated: jump.animated, flash: jump.flash)
        }
        view.setRecall(recall?.passage, id: recall?.id, letters: recallLetters, whole: recall?.whole ?? true)
    }

    @MainActor
    final class Coordinator: ReaderViewDelegate {
        let store: Store
        var marksVersion = 0
        var jump: UUID?
        var onBooksPan: ((UIGestureRecognizer.State, CGFloat, CGFloat) -> Void)?

        init(store: Store) { self.store = store }

        func reader(_ reader: ReaderView, didReach chapter: Int, verse: Int) {
            store.reached(chapter, verse: verse)
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
            guard store.selection == nil, store.recall == nil, store.barsHidden != isReadingOn else { return }
            store.barsHidden = isReadingOn
        }

        func reader(_ reader: ReaderView, booksPan state: UIGestureRecognizer.State, translation: CGFloat, velocity: CGFloat) {
            onBooksPan?(state, translation, velocity)
        }

        func reader(_ reader: ReaderView, recallChanged status: RecallStatus) {
            let run = store.recall?.id
            DispatchQueue.main.async { [weak self] in
                guard let self, self.store.recall?.id == run else { return }
                self.store.recallChanged(status)
            }
        }
    }
}
