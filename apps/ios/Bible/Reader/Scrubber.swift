import UIKit

@MainActor
protocol ScrubberViewDelegate: AnyObject {
    /// A finger held still on the rail long enough to pick it up.
    func scrubberDidBegin(_ scrubber: ScrubberView)
    /// The finger let go at a chapter (to land on its head), or at a verse at Verse speed.
    func scrubber(_ scrubber: ScrubberView, didScrubTo chapter: Int, verse: Int, atVerse: Bool)
}

/// The Scrubber: a rail along the reader's right edge that spans the whole Bible. It shows while
/// the reader scrolls and for two seconds after. A short hold on it picks it up; dragging then
/// previews a place in a label clear of the finger, and letting go jumps there. Dragging inward
/// slows it from Bible speed to Chapter speed and Verse speed (the core's `ScrubGesture` is the
/// model). A drag never touches SwiftUI state, only letting go.
///
/// The view itself takes no touches, so a tap or a flick on the rail still reaches the reader.
/// Its `hold` goes on a view over both, the reader and the Scrubber.
final class ScrubberView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: ScrubberViewDelegate?

    /// The rail's width at the right edge: where a hold picks it up.
    static let railWidth: CGFloat = 44
    /// How long a finger holds still on the rail to pick it up. A tap is shorter, and a flick
    /// moves first.
    static let holdDuration: TimeInterval = 0.2

    /// The hold that picks up the rail and then drags it.
    let hold = UILongPressGestureRecognizer()

    /// Whether the reader is being dragged or is still moving after a fling. The rail doesn't
    /// hide while it is. (Asked rather than tracked: a touch that stops a fling may not say so.)
    var isReaderScrolling: () -> Bool = { false }

    /// The reader's reading line, just under the toolbar: the rail starts there.
    var readingLine: CGFloat = 100 {
        didSet { if readingLine != oldValue { setNeedsLayout() } }
    }

    /// While verses are selected the rail stays hidden.
    var isSuppressed = false {
        didSet {
            guard isSuppressed != oldValue else { return }
            if isSuppressed { setVisible(false) } else if UIAccessibility.isVoiceOverRunning { show() }
        }
    }

    private var theme = Theme.light
    private var makeAxis: (() -> ScrubAxis)?
    private var builtAxis: ScrubAxis?
    /// Where the reader is, and that place on the axis once it's been worked out.
    private var resting = Position(chapter: 0, verse: 1)
    private var restingPosition: Double?

    private var gesture: ScrubGesture?
    /// Where the drag is, while there is one.
    private var point: ScrubPoint?
    private var finger = CGPoint.zero

    private var isVisible = false
    private var isVoiceOverFocused = false
    private var hideTask: Task<Void, Never>?

    private let rail = Rail()
    private let track = UIView()
    private var ticks: [(view: UIView, landmark: ScrubLandmark)] = []
    private let thumb = UIView()
    private let bubble = UIView()
    private let bubbleGlass: UIVisualEffectView
    /// Before iOS 26 the label is the system material, which needs the design's border and shadow.
    private let isMaterial: Bool
    private let sectionLabel = UILabel()
    private let referenceLabel = UILabel()
    private let speedLabel = UILabel()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let tick = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        let glass = ScrubberView.makeGlass()
        bubbleGlass = glass.view
        isMaterial = glass.isMaterial
        super.init(frame: frame)
        isAccessibilityElement = false
        hold.minimumPressDuration = Self.holdDuration
        hold.delegate = self
        hold.addTarget(self, action: #selector(held(_:)))
        rail.owner = self
        rail.isAccessibilityElement = true
        rail.accessibilityLabel = "Scrubber"
        rail.accessibilityHint = "Swipe up or down to go to the next or previous chapter."
        rail.accessibilityIdentifier = "scrubber"
        rail.accessibilityTraits = .adjustable
        rail.accessibilityElementsHidden = true
        rail.alpha = 0
        addSubview(rail)
        track.layer.cornerRadius = 1
        track.isUserInteractionEnabled = false
        rail.addSubview(track)
        thumb.isUserInteractionEnabled = false
        thumb.layer.borderWidth = 2
        rail.addSubview(thumb)

        bubble.isUserInteractionEnabled = false
        bubble.isHidden = true
        bubble.accessibilityElementsHidden = true
        if isMaterial {
            bubble.layer.shadowOffset = CGSize(width: 0, height: 4)
            bubble.layer.shadowRadius = 12
        }
        bubbleGlass.frame = bubble.bounds
        bubbleGlass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        bubble.addSubview(bubbleGlass)
        for label in [sectionLabel, referenceLabel, speedLabel] {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.textAlignment = .right
            bubbleGlass.contentView.addSubview(label)
        }
        addSubview(bubble)
        updateFonts()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.updateFonts()
            self.render()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(voiceOverChanged), name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil)
        apply(theme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The design's glass, as `glass(in:)` draws it: Liquid Glass from iOS 26, the system material
    /// before it.
    private static func makeGlass() -> (view: UIVisualEffectView, isMaterial: Bool) {
        #if compiler(>=6.2)
            if #available(iOS 26, *) {
                let view = UIVisualEffectView(effect: UIGlassEffect())
                view.cornerConfiguration = .corners(radius: .fixed(16))
                return (view, false)
            }
        #endif
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.layer.borderWidth = 0.5
        return (view, true)
    }

    // MARK: Configuration

    func configure(theme: Theme) {
        guard theme != self.theme else { return }
        self.theme = theme
        apply(theme)
    }

    /// Where the axis for the reading translation comes from. It's built when the rail first
    /// needs it, so opening the app doesn't wait for it.
    func setAxis(_ make: @escaping () -> ScrubAxis) {
        makeAxis = make
        builtAxis = nil
        restingPosition = nil
        if isVisible || UIAccessibility.isVoiceOverRunning {
            show()
            render()
        }
    }

    private var axis: ScrubAxis? {
        if builtAxis == nil, let makeAxis {
            builtAxis = makeAxis()
            makeTicks()
        }
        return builtAxis
    }

    /// The reader's place, where the thumb rests.
    func rest(at position: Position) {
        guard position != resting else { return }
        resting = position
        restingPosition = nil
        if isVisible && gesture == nil { render() }
    }

    private func restingPlace(_ axis: ScrubAxis) -> Double {
        if let restingPosition { return restingPosition }
        let p = axis.position(chapter: UInt16(resting.chapter), verse: UInt8(clamping: resting.verse))
        restingPosition = p
        return p
    }

    // MARK: Showing

    func readerDidBeginScrolling() {
        show()
    }

    func readerDidEndScrolling() {
        linger()
    }

    /// Shows the rail for a while.
    func show() {
        guard !isSuppressed, axis != nil else { return }
        setVisible(true)
        linger()
    }

    /// Hides the rail two seconds after the last scroll, drag or VoiceOver focus. With VoiceOver
    /// on it stays: there is no scrolling to call it up by.
    private func linger() {
        hideTask?.cancel()
        guard isVisible, gesture == nil, !isVoiceOverFocused, !UIAccessibility.isVoiceOverRunning else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            if isReaderScrolling() { linger() } else { setVisible(false) }
        }
    }

    private func setVisible(_ visible: Bool) {
        if !visible {
            hideTask?.cancel()
            isVoiceOverFocused = false
            if gesture != nil { end(cancelled: true) }
        }
        guard visible != isVisible else { return }
        isVisible = visible
        rail.accessibilityElementsHidden = !visible
        if visible { render() }
        let change = { self.rail.alpha = visible ? 1 : 0 }
        if UIAccessibility.isReduceMotionEnabled {
            change()
        } else {
            UIView.animate(
                withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                animations: change)
        }
    }

    @objc private func voiceOverChanged() {
        if UIAccessibility.isVoiceOverRunning { show() } else { linger() }
    }

    fileprivate func focusChanged(_ focused: Bool) {
        isVoiceOverFocused = focused
        if focused { hideTask?.cancel() } else { linger() }
    }

    // MARK: Touches

    // Touches go through to the reader; only `hold` acts on them.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

    /// The hold takes only touches that start on the rail while it shows.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isVisible, !isSuppressed, rail.frame.contains(touch.location(in: self)) else { return false }
        impact.prepare()
        return true
    }

    /// The rail may have hidden while the finger held still; then the reader has the touch.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === hold else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        return isVisible && !isSuppressed && axis != nil
    }

    /// Once the hold has picked the rail up, the finger keeps it as it moves inward, off the rail.
    @objc private func held(_ hold: UILongPressGestureRecognizer) {
        let p = hold.location(in: self)
        switch hold.state {
        case .began: begin(at: p)
        case .changed: move(to: p)
        case .ended: end(cancelled: false)
        case .cancelled, .failed: end(cancelled: true)
        default: break
        }
    }

    private func begin(at p: CGPoint) {
        guard isVisible, gesture == nil, let axis else { return }
        hideTask?.cancel()
        let gesture = ScrubGesture(
            axis: axis, resting: restingPlace(axis), y: Double(p.y),
            trackTop: Double(rail.frame.minY + track.frame.minY), trackHeight: Double(track.bounds.height))
        let point = gesture.point()
        self.gesture = gesture
        self.point = point
        finger = p
        // Only now the drag is under way: stopping a glide ends the reader's scroll, and the end of
        // a scroll would otherwise set the rail to hide mid-drag.
        delegate?.scrubberDidBegin(self)
        // The hold has picked the rail up.
        impact.impactOccurred()
        tick.prepare()
        bubble.isHidden = false
        render()
    }

    private func move(to p: CGPoint) {
        guard let gesture, let previous = point else { return }
        let next = gesture.moveTo(y: Double(p.y), inward: Double(rail.frame.minX - p.x))
        if next.speed != previous.speed { impact.impactOccurred() }
        if (next.speed == .bible && next.book != previous.book)
            || (next.speed == .chapter && next.chapterIndex != previous.chapterIndex)
        {
            tick.selectionChanged()
        }
        point = next
        finger = p
        render()
    }

    private func end(cancelled: Bool) {
        guard let point else { return }
        gesture = nil
        self.point = nil
        bubble.isHidden = true
        if !cancelled {
            delegate?.scrubber(
                self, didScrubTo: Int(point.chapterIndex), verse: Int(point.verse), atVerse: point.speed == .verse)
        }
        render()
        linger()
    }

    /// VoiceOver's swipe up and down: the next or previous chapter.
    fileprivate func adjust(by delta: Int) {
        let next = min(max(resting.chapter + delta, 0), ReaderView.chapterCount - 1)
        guard next != resting.chapter else { return }
        delegate?.scrubber(self, didScrubTo: next, verse: 1, atVerse: false)
        rest(at: Position(chapter: next, verse: 1))
        tick.selectionChanged()
    }

    fileprivate var restingReference: String? {
        guard let axis else { return nil }
        return axis.point(position: restingPlace(axis), speed: resting.verse > 1 ? .verse : .chapter).reference
    }

    // MARK: Drawing

    private func apply(_ theme: Theme) {
        track.backgroundColor = theme.ink3.withAlphaComponent(0.35)
        for (view, landmark) in ticks {
            view.backgroundColor = landmark.testament ? theme.ink2 : theme.ink3
        }
        thumb.backgroundColor = theme.accent
        thumb.layer.borderColor = theme.paper.cgColor
        if isMaterial {
            bubble.layer.shadowColor = UIColor.black.cgColor
            bubble.layer.shadowOpacity = theme.isDark ? 0.3 : 0.08
            bubbleGlass.layer.borderColor = theme.border.cgColor
        }
        sectionLabel.textColor = theme.accent
        referenceLabel.textColor = theme.ink
        speedLabel.textColor = theme.ink2
    }

    private func makeTicks() {
        for (view, _) in ticks { view.removeFromSuperview() }
        ticks = (builtAxis?.landmarks() ?? []).map { landmark in
            let view = UIView()
            view.isUserInteractionEnabled = false
            track.addSubview(view)
            return (view, landmark)
        }
        apply(theme)
        setNeedsLayout()
    }

    private func updateFonts() {
        sectionLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: Fonts.inter(11))
        referenceLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: Fonts.literata(26))
        speedLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: Fonts.inter(14, weight: 500))
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let top = readingLine - 8
        let bottom = bounds.height - safeAreaInsets.bottom
        // Inside the safe area, clear of a landscape notch or Dynamic Island.
        rail.frame = CGRect(
            x: bounds.maxX - safeAreaInsets.right - Self.railWidth, y: top, width: Self.railWidth,
            height: max(bottom - top, 88))
        track.frame = CGRect(x: 31, y: 22, width: 2, height: max(1, rail.bounds.height - 44))
        for (view, landmark) in ticks {
            let strong = landmark.testament
            view.frame = CGRect(
                x: strong ? -7 : -4, y: (landmark.fraction * track.bounds.height).rounded(),
                width: strong ? 16 : 10, height: strong ? 2 : 1)
        }
        render()
    }

    private func render() {
        guard isVisible, let axis else { return }
        let fraction = point?.fraction ?? restingPlace(axis) / axis.length()
        let thumbY = track.frame.minY + fraction * track.bounds.height
        let dragging = point != nil
        let width: CGFloat = dragging ? 16 : 12
        thumb.frame = CGRect(x: 32 - width / 2, y: thumbY - 22, width: width, height: 44)
        thumb.layer.cornerRadius = width / 2

        guard let point else { return }
        sectionLabel.attributedText = NSAttributedString(
            string: point.section.uppercased(),
            attributes: [.kern: sectionLabel.font.pointSize * 0.12, .font: sectionLabel.font as Any])
        sectionLabel.textAlignment = .right
        referenceLabel.text = point.reference
        speedLabel.text = point.speed.label

        // Level with the rail, below the toolbar, which draws over the reader and would cover it.
        let area = CGRect(
            x: safeAreaInsets.left + 8, y: rail.frame.minY,
            width: bounds.width - safeAreaInsets.left - safeAreaInsets.right - 16, height: rail.frame.height)
        let labelFrame = Self.placeLabel(
            finger: finger, in: area, right: rail.frame.minX - 8, size: { self.labelSize(within: $0) })
        layoutLabels(width: labelFrame.width)
        // Straight there, never animated: on its way it could pass under the finger.
        bubble.frame = labelFrame
        if isMaterial {
            bubble.layer.shadowPath = UIBezierPath(roundedRect: bubble.bounds, cornerRadius: 16).cgPath
        }
    }

    // MARK: The label's place

    /// How far above the finger's touch the label stays, so the tip of a thumb doesn't cover it.
    static let labelClearanceAbove: CGFloat = 72
    /// How far to the side of the touch the label stays when it's beside the finger: past half a
    /// thumb's width.
    static let labelClearanceBeside: CGFloat = 64
    /// The narrowest the label gets; narrower than its text, the text wraps.
    static let labelMinWidth: CGFloat = 120

    /// Where the label goes for a finger at `finger`, inside `area`. Its place is above the
    /// finger, right-aligned at `right` by the rail, where neither a thumb nor a finger reaching
    /// up from below covers it. Near the top there's no room above, so it goes beside the finger
    /// and no lower than the touch: on the left if it fits, as for a right thumb on the rail, or
    /// else (a finger far inward) on the right. `size` measures the label at most a given width.
    static func placeLabel(
        finger: CGPoint, in area: CGRect, right: CGFloat, size: (CGFloat) -> CGSize
    ) -> CGRect {
        let right = min(right, area.maxX)
        let above = size(right - area.minX)
        let aboveY = finger.y - labelClearanceAbove - above.height
        if aboveY >= area.minY {
            return CGRect(x: right - above.width, y: aboveY, width: above.width, height: above.height)
        }
        // Beside: as high as the area allows, its bottom no lower than the touch. A label taller
        // than the screen (the largest text, in landscape) keeps its top on it.
        func beside(_ size: CGSize, x: CGFloat) -> CGRect {
            let y = max(area.minY, min(finger.y - size.height, area.maxY - size.height))
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
        let leftEdge = min(finger.x - labelClearanceBeside, right)
        let rightEdge = finger.x + labelClearanceBeside
        let leftRoom = leftEdge - area.minX
        let rightRoom = area.maxX - rightEdge
        if leftRoom >= labelMinWidth || leftRoom >= rightRoom {
            let s = size(max(leftRoom, 1))
            return beside(s, x: leftEdge - s.width)
        }
        let s = size(rightRoom)
        return beside(s, x: rightEdge)
    }

    /// The label's size when it may be at most `width` wide; past that its text wraps.
    private func labelSize(within width: CGFloat) -> CGSize {
        let labels = [sectionLabel, referenceLabel, speedLabel]
        let fit = CGSize(width: max(1, width - 28), height: .greatestFiniteMagnitude)
        let textWidth = labels.map { $0.sizeThatFits(fit).width }.max() ?? 0
        let labelWidth = min(width, max(Self.labelMinWidth, ceil(textWidth) + 28))
        let wrap = CGSize(width: labelWidth - 28, height: .greatestFiniteMagnitude)
        let height = labels.reduce(CGFloat(12 + 8 - 4)) { $0 + ceil($1.sizeThatFits(wrap).height) + 4 }
        return CGSize(width: labelWidth, height: height)
    }

    private func layoutLabels(width: CGFloat) {
        var y: CGFloat = 12
        for label in [sectionLabel, referenceLabel, speedLabel] {
            let size = label.sizeThatFits(CGSize(width: width - 28, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: 14, y: y, width: width - 28, height: ceil(size.height))
            y += ceil(size.height) + 4
        }
    }
}

extension ScrubSpeed {
    var label: String {
        switch self {
        case .bible: "Bible speed"
        case .chapter: "Chapter speed"
        case .verse: "Verse speed"
        }
    }
}

/// The rail, and the Scrubber as one adjustable VoiceOver element.
private final class Rail: UIView {
    weak var owner: ScrubberView?

    override var accessibilityValue: String? {
        get { owner?.restingReference }
        set {}
    }

    override func accessibilityIncrement() { owner?.adjust(by: 1) }
    override func accessibilityDecrement() { owner?.adjust(by: -1) }
    /// A double tap would otherwise tap the reader under the rail.
    override func accessibilityActivate() -> Bool { true }

    override func accessibilityElementDidBecomeFocused() {
        super.accessibilityElementDidBecomeFocused()
        owner?.focusChanged(true)
    }

    override func accessibilityElementDidLoseFocus() {
        super.accessibilityElementDidLoseFocus()
        owner?.focusChanged(false)
    }
}
