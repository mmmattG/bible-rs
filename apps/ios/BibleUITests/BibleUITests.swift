import XCTest

/// The main flows, driven through the interface. Each test starts the app with no saved data
/// (`--uitest`), so it opens at John 1 in the KJV.
final class BibleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
    }

    private var reference: XCUIElement { app.buttons["reference"] }

    private func verse(_ id: String) -> XCUIElement { app.staticTexts[id] }

    /// Waits for the toolbar to name a chapter.
    private func expectChapter(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = NSPredicate(format: "label BEGINSWITH %@", title + ".")
        let found = XCTNSPredicateExpectation(predicate: shown, object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed, "expected \(title), saw \(reference.label)", file: file, line: line)
    }

    func testOpensAtJohnOne() {
        expectChapter("John 1")
        XCTAssertTrue(verse("John 1:1").exists)
        XCTAssertTrue(verse("John 1:1").label.contains("In the beginning was the Word"))
    }

    func testScrollingReadsOnIntoTheNextChapters() {
        for _ in 0..<12 { app.swipeUp(velocity: .fast) }
        let title = reference.label
        XCTAssertFalse(title.hasPrefix("John 1."), "still at \(title)")
        XCTAssertTrue(title.hasPrefix("John"), "left John: \(title)")
        // And back, across the chapter boundary into Luke.
        for _ in 0..<24 { app.swipeDown(velocity: .fast) }
        let shown = NSPredicate(format: "label BEGINSWITH 'Luke'")
        let back = XCTNSPredicateExpectation(predicate: shown, object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed, "saw \(reference.label)")
    }

    func testJumpsToATypedReference() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").waitForExistence(timeout: 3))
        XCTAssertTrue(verse("Romans 8:28").isHittable)
    }

    func testRotatingKeepsYourPlace() {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").waitForExistence(timeout: 3))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            expectChapter("Romans 8")
            XCTAssertTrue(verse("Romans 8:28").isHittable, "Romans 8:28 left the screen at orientation \(orientation.rawValue)")
        }
    }

    func testPicksABookAndChapter() {
        reference.tap()
        let romans = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Romans'")).firstMatch
        XCTAssertTrue(romans.waitForExistence(timeout: 3))
        romans.tap()
        let twelve = app.buttons["Romans 12"]
        XCTAssertTrue(twelve.waitForExistence(timeout: 3))
        twelve.tap()
        expectChapter("Romans 12")
        XCTAssertTrue(verse("Romans 12:1").label.contains("living sacrifice"))
    }

    func testPsalmsOpenFromAReference() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("ps 23\n")
        expectChapter("Psalm 23")
        XCTAssertTrue(verse("Psalm 23:1").waitForExistence(timeout: 3))
        XCTAssertTrue(verse("Psalm 23:1").label.contains("shepherd"))
    }

    func testSwitchesTranslation() {
        XCTAssertTrue(verse("John 1:5").label.contains("shineth in darkness"))
        app.buttons["translation"].tap()
        let web = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'WEB'")).firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 3))
        web.tap()
        let switched = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS 'shines in the darkness'"), object: verse("John 1:5"))
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 5), .completed, verse("John 1:5").label)
        expectChapter("John 1")
    }

    func testReopensWhereYouLeftOff() {
        reference.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("rom 8:28\n")
        expectChapter("Romans 8")
        app.buttons["translation"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BSB'")).firstMatch.tap()

        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launchArguments = ["--uitest", "--keep-data"]
        app.launch()
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        expectChapter("Romans 8")
        XCTAssertTrue(verse("Romans 8:28").isHittable)
        XCTAssertTrue(app.buttons["translation"].label.contains("Berean"), app.buttons["translation"].label)
    }

    func testSearchFindsAndOpensAVerse() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("love one another")
        let hit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 13:34'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        hit.tap()
        expectChapter("John 13")
        XCTAssertTrue(verse("John 13:34").isHittable)
    }

    func testSearchLoadsMoreAsYouScroll() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("lamb\n")
        XCTAssertTrue(row("Genesis 21:28").waitForExistence(timeout: 5))
        // The last of 175 hits, on the fourth page.
        let last = row("Revelation 22:3")
        for _ in 0..<40 where !last.exists { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(last.exists)
    }

    func testMisspelledSearchOffersASuggestion() {
        app.buttons["search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("bethsaida pool")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Search “bethesda pool”'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'John 5:2'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testHighlightBookmarkAndNoteShowInStudy() {
        let first = verse("John 1:1")
        first.tap()
        app.selectionAction("Highlight Green").tap()

        first.tap()
        app.selectionAction("Bookmark").tap()

        verse("John 1:3").tap()
        app.selectionAction("Note").tap()
        let note = app.textFields["Write a note"].exists ? app.textFields["Write a note"] : app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.typeText("All things, without exception.")
        app.buttons["Save"].tap()

        app.buttons["study"].tap()
        XCTAssertTrue(row("John 1:1").waitForExistence(timeout: 3), "bookmark listed")
        app.buttons["Highlights"].tap()
        XCTAssertTrue(row("John 1:1").waitForExistence(timeout: 3), "highlight listed")
        app.buttons["Notes"].tap()
        XCTAssertTrue(row("John 1:3").waitForExistence(timeout: 3), "note listed")
        XCTAssertTrue(row("John 1:3").label.contains("without exception"))
    }

    func testCopiesAVerseWithItsReference() {
        verse("John 1:4").tap()
        app.selectionAction("Copy").tap()
        XCTAssertTrue(app.staticTexts["Copied John 1:4"].waitForExistence(timeout: 3))
    }

    func testThemeAndTextSizeApplyAtOnce() {
        app.buttons["settings"].tap()
        app.buttons["Dark theme"].tap()
        let slider = app.sliders["Text size"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        slider.adjust(toNormalizedSliderPosition: 0.9)
        app.buttons["Done"].tap()
        XCTAssertTrue(verse("John 1:1").exists)
    }

    func testScrollingDoesNotHitch() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
        }
    }

    // MARK: Scrubber
    //
    // A short hold picks the rail up. A drag is then one straight line, so it moves at Bible speed
    // until it has come far enough inward to slow down. These drags move only inward once they're
    // slower, or move only along the rail.

    func testScrubberJumpsAtBibleSpeedAndGoesBack() {
        let rail = revealScrubber()
        // A press away from the thumb starts where it lands: the top of the track is Genesis. The
        // middle of the Bible, by verses, is in the Psalms.
        scrubberDrag(from: trackPoint(rail, 0), to: trackPoint(rail, 0.5))
        expectBook("Psalm")
        let back = app.buttons["scrubber-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        XCTAssertTrue(back.label.hasPrefix("Back to John 1"), back.label)
        back.tap()
        expectChapter("John 1")
        XCTAssertFalse(back.exists)
    }

    func testScrubberLandsOnAVerseWithoutSelectingIt() {
        let rail = revealScrubber()
        // From the thumb 150 pt inward is Verse speed, which starts at the chapter's first verse.
        let start = thumbPoint(rail)
        scrubberDrag(from: start, to: start.withOffset(CGVector(dx: -150 - 32, dy: 1)))
        expectChapter("John 1")
        XCTAssertTrue(verse("John 1:1").isHittable)
        XCTAssertFalse(app.buttons["Clear selection"].exists)
        XCTAssertTrue(app.buttons["scrubber-back"].waitForExistence(timeout: 3))
    }

    func testScrubberStaysPutInTheSameChapterAndBackStepsThroughJumps() {
        let rail = revealScrubber()
        // Into Chapter speed (80 pt inward) and let go without moving a chapter: nothing moves.
        let start = thumbPoint(rail)
        scrubberDrag(from: start, to: start.withOffset(CGVector(dx: -80 - 32, dy: 0)))
        expectChapter("John 1")
        let back = app.buttons["scrubber-back"]
        XCTAssertFalse(back.exists)
        // Holding still on the rail and letting go jumps there.
        hold(trackPoint(rail, 0.63))
        expectBook("Jeremiah")
        hold(trackPoint(rail, 0.295))
        expectBook("1 Kings")
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        expectBook("Jeremiah")
        XCTAssertTrue(back.label.hasPrefix("Back to John 1"), back.label)
        // Scrolling by hand lets go of the rest.
        app.swipeUp()
        XCTAssertTrue(back.waitForNonExistence(timeout: 3))
    }

    func testATapOnTheRailGoesToTheReader() {
        let barsShown = reference.isHittable
        let rail = revealScrubber()
        // A tap is too short to pick the rail up. The reader has it: it selects the verse at the
        // edge, or shows or hides the bars, and nothing jumps.
        trackPoint(rail, 0.1).tap()
        let selected = app.buttons["Clear selection"].waitForExistence(timeout: 1)
        XCTAssertTrue(selected || reference.isHittable != barsShown, "the reader didn't get the tap")
        XCTAssertTrue(verse("John 1:1").exists)
        XCTAssertFalse(app.buttons["scrubber-back"].exists)
    }

    func testAFlickOnTheRailScrollsTheReader() {
        XCTAssertTrue(verse("John 1:1").isHittable)
        let rail = revealScrubber()
        // A flick moves before the hold is up, so it scrolls the reader instead.
        trackPoint(rail, 0.6).press(
            forDuration: 0, thenDragTo: trackPoint(rail, 0.1), withVelocity: .fast, thenHoldForDuration: 0)
        expectBook("John")
        XCTAssertFalse(verse("John 1:1").isHittable)
        XCTAssertFalse(app.buttons["scrubber-back"].exists)
    }

    func testScrubberHidesWhileVersesAreSelected() {
        _ = revealScrubber()
        verse("John 1:4").tap()
        XCTAssertTrue(app.buttons["Clear selection"].waitForExistence(timeout: 3))
        XCTAssertFalse(scrubber.exists)
    }

    private var scrubber: XCUIElement { app.descendants(matching: .any)["scrubber"] }

    /// Scrolls a little, which shows the rail for two seconds, and returns where the rail is. Just
    /// after a simulator boots, the app can be too busy to notice the first small scroll, so it
    /// tries again. The frame is read once: each read takes time, and the rail doesn't wait.
    private func revealScrubber() -> CGRect {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        for _ in 0..<3 where !scrubber.exists {
            start.press(
                forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -24)), withVelocity: .slow,
                thenHoldForDuration: 0)
            _ = scrubber.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(scrubber.exists)
        return scrubber.frame
    }

    /// A point on the rail's track, `fraction` of the way through the Bible by verses. The track
    /// runs the rail's height less 22 pt at each end.
    private func trackPoint(_ rail: CGRect, _ fraction: CGFloat) -> XCUICoordinate {
        let y = rail.minY + 22 + (rail.height - 44) * fraction
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: rail.maxX - 12, dy: y))
    }

    /// Where the thumb rests at John 1, which starts 26,045 of the KJV's 31,102 verses in.
    private func thumbPoint(_ rail: CGRect) -> XCUICoordinate {
        trackPoint(rail, 26_045 / 31_102)
    }

    /// Holds to pick the rail up, then drags and holds two seconds before letting go, as someone
    /// reading the label would.
    private func scrubberDrag(from start: XCUICoordinate, to end: XCUICoordinate) {
        start.press(forDuration: 0.5, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 2)
    }

    /// Holds still on the rail long enough to pick it up, then lets go.
    private func hold(_ point: XCUICoordinate) {
        point.press(forDuration: 0.5)
    }

    /// Waits for the toolbar to name a chapter of a book ("Psalm" for any psalm).
    private func expectBook(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = NSPredicate(format: "label BEGINSWITH %@", name + " ")
        let found = XCTNSPredicateExpectation(predicate: shown, object: reference)
        XCTAssertEqual(XCTWaiter.wait(for: [found], timeout: 5), .completed, "expected \(name), saw \(reference.label)", file: file, line: line)
    }

    private func row(_ reference: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", reference)).firstMatch
    }
}

extension XCUIApplication {
    /// A button in the selection bar, once the bar has slid into place (0.28 s): a tap while it
    /// moves lands on the text behind it.
    func selectionAction(_ label: String) -> XCUIElement {
        let button = buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 3), label)
        usleep(400_000)
        return button
    }
}
