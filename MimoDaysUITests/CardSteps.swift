import XCTest

extension XCUIApplication {
    /// The element with `id` on screen: the pager's neighbours off screen are skipped, as asking whether one is
    /// hittable fails the test.
    func shown(_ id: String, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            let screen = frame
            let element = descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.first {
                $0.exists && screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.isHittable
            }
            if let element { return element }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.2))
        } while Date.now < deadline
        return nil
    }

    /// U35 on whichever screen opened the card: a tap on the selfie window swaps the cameras and another swaps them
    /// back; the folded corner turns the card to its back and round to the front again.
    @MainActor
    func swapAndFlipTheCard(file: StaticString = #filePath, line: UInt = #line) {
        guard let window = shown("viewer.selfieWindow") else { return XCTFail("no selfie window", file: file, line: line) }
        XCTAssertFalse(window.isSelected, file: file, line: line)
        window.tap()
        XCTAssertTrue(shown("viewer.selfieWindow")?.isSelected == true, "the cameras didn't swap", file: file, line: line)
        shown("viewer.selfieWindow")?.tap()
        XCTAssertTrue(shown("viewer.selfieWindow")?.isSelected == false, "the cameras didn't swap back", file: file, line: line)
        guard let fold = shown("card.fold") else { return XCTFail("no folded corner", file: file, line: line) }
        fold.tap()
        XCTAssertNil(shown("viewer.media", timeout: 3), "the front is still showing", file: file, line: line)
        shown("card.fold")?.tap()
        XCTAssertNotNil(shown("viewer.media"), "the front didn't come back", file: file, line: line)
    }
}
