import SwiftUI
import UIKit

/// Along the foot of the reader while recalling: back, the passage, what to do, and once it's all
/// shown, the grades.
struct RecallBar: View {
    @Environment(Store.self) private var store
    let theme: Theme
    @State private var scrubbingStatus: RecallStatus?

    var body: some View {
        if let run = store.recall {
            let displayedStatus = scrubbingStatus ?? run.status
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        store.endRecall()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(theme.ink))
                            .frame(width: 36, height: 36)
                            .background(Color(theme.fill), in: Circle())
                    }
                    .accessibilityLabel("Back to reading")
                    .accessibilityIdentifier("end-recall")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(run.passage.reference)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(theme.ink))
                            if run.queue.count > 1 {
                                Text("\(run.index + 1) of \(run.queue.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color(theme.ink3))
                            }
                        }
                        Text(status(displayedStatus))
                            .font(.footnote)
                            .foregroundStyle(Color(theme.ink2))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if displayedStatus.unavailable {
                        skip
                    } else if !displayedStatus.done {
                        hints
                    }
                }
                if !run.status.unavailable {
                    RecallProgressSlider(progress: run.status.progress, theme: theme, seek: store.seekRecall) { editing in
                        withAnimation(editing ? nil : .smooth(duration: 0.28)) {
                            scrubbingStatus = editing ? run.status : nil
                        }
                    }
                    .id(run.id)
                    .frame(height: 44)
                }
                if displayedStatus.done {
                    grades.disabled(scrubbingStatus != nil)
                }
            }
            .padding(14)
            .frame(maxWidth: 520)
            .glass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), theme: theme, interactive: false)
            .onChange(of: run.id) { scrubbingStatus = nil }
        }
    }

    private func status(_ status: RecallStatus) -> String {
        if status.unavailable { return "Not all of it is in this translation" }
        if status.done { return "How well did you know it?" }
        return status.started ? "Tap for the next word, or slide to check" : "Say it from memory, then tap or slide to check"
    }

    /// On to the next passage, leaving this one ungraded.
    private var skip: some View {
        Button("Skip") { store.skipRecall() }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(theme.onAccent))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(theme.accent), in: Capsule())
            .accessibilityHint("Goes on to the next passage without grading this one")
            .accessibilityIdentifier("skip-recall")
    }

    /// The hint style, as a pop-up of its two choices.
    private var hints: some View {
        let letters = Binding(get: { store.settings.recallLetters }, set: { store.settings.recallLetters = $0 })
        return Menu {
            Picker("Hints", selection: letters) {
                Text("First letters").tag(true)
                Text("No hints").tag(false)
            }
        } label: {
            HStack(spacing: 4) {
                Text(letters.wrappedValue ? "First letters" : "No hints")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(theme.ink))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(theme.fill), in: Capsule())
        }
        .accessibilityLabel("Hints")
        .accessibilityValue(letters.wrappedValue ? "First letters" : "No hints")
    }

    private var grades: some View {
        HStack(spacing: 8) {
            ForEach([RecallGrade.again, .hard, .good, .easy], id: \.self) { g in
                let on = g == .good
                Button {
                    store.grade(g)
                } label: {
                    Text(g.label)
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .foregroundStyle(on ? Color(theme.onAccent) : Color(theme.ink))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Color(theme.accent) : Color(theme.fill), in: Capsule())
                }
                .accessibilityIdentifier("grade-\(g.label)")
            }
        }
    }
}

private struct RecallProgressSlider: UIViewRepresentable {
    let progress: Double
    let theme: Theme
    let seek: (Double) -> Void
    let editingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FingerSlider {
        let slider = FingerSlider()
        slider.isOpaque = false
        slider.contentMode = .redraw
        slider.isAccessibilityElement = true
        slider.accessibilityTraits = .adjustable
        slider.accessibilityLabel = "Passage revealed"
        slider.accessibilityIdentifier = "recall-progress"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.editingChanged = { [weak coordinator = context.coordinator] active in
            coordinator?.parent.editingChanged(active)
        }
        return slider
    }

    func updateUIView(_ slider: FingerSlider, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if slider.theme != theme { slider.theme = theme }
        guard !slider.isTracking else { return }
        if let pending = coordinator.pending, abs(progress - pending) > 0.0001 { return }
        coordinator.pending = nil
        slider.progress = progress
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RecallProgressSlider
        var pending: Double?

        init(_ parent: RecallProgressSlider) { self.parent = parent }

        @objc func changed(_ slider: FingerSlider) {
            pending = abs(slider.progress - parent.progress) < 0.0001 ? nil : slider.progress
            parent.seek(slider.progress)
        }
    }

    final class FingerSlider: UIControl {
        var editingChanged: ((Bool) -> Void)?
        var progress: Double = 0 { didSet { setNeedsDisplay() } }
        var theme = Theme.light { didSet { setNeedsDisplay() } }
        private let radius: CGFloat = 14

        override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 44) }

        override var accessibilityValue: String? {
            get { "\(Int((progress * 100).rounded())) percent" }
            set {}
        }

        override func draw(_ rect: CGRect) {
            let width = max(bounds.width - 2 * radius, 0)
            let x = bounds.minX + radius + width * CGFloat(progress)
            let track = CGRect(x: bounds.minX + radius, y: bounds.midY - 3, width: width, height: 6)
            theme.fillStrong.setFill()
            UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
            theme.accent.setFill()
            UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: x - track.minX, height: 6), cornerRadius: 3).fill()
            let thumb = UIBezierPath(ovalIn: CGRect(x: x - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2))
            let context = UIGraphicsGetCurrentContext()
            context?.saveGState()
            context?.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            UIColor.white.setFill()
            thumb.fill()
            context?.restoreGState()
            theme.border.setStroke()
            thumb.lineWidth = 0.5
            thumb.stroke()
        }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            editingChanged?(true)
            follow(touch)
            return true
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            follow(touch)
            return true
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch { follow(touch) }
            editingChanged?(false)
        }

        override func cancelTracking(with event: UIEvent?) {
            editingChanged?(false)
        }

        override func accessibilityIncrement() { adjust(by: 0.05) }
        override func accessibilityDecrement() { adjust(by: -0.05) }

        private func adjust(by amount: Double) {
            editingChanged?(true)
            progress = (progress + amount).clamped(to: 0...1)
            sendActions(for: .valueChanged)
            editingChanged?(false)
        }

        private func follow(_ touch: UITouch) {
            let width = max(bounds.width - 2 * radius, 1)
            progress = Double(((touch.location(in: self).x - bounds.minX - radius) / width).clamped(to: 0...1))
            sendActions(for: .valueChanged)
        }
    }
}

extension RecallGrade {
    var label: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}
