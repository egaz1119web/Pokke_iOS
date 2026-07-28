import XCTest

final class ReviewPromptTests: XCTestCase {

    private let day: EpochMillis = 24 * 60 * 60 * 1000
    private let launch: EpochMillis = 1_700_000_000_000

    private func shouldRequest(
        itemCount: Int,
        daysElapsed: Int64,
        alreadyRequested: Bool = false
    ) -> Bool {
        ReviewPrompt.shouldRequest(
            itemCount: itemCount,
            firstLaunchAt: launch,
            alreadyRequested: alreadyRequested,
            now: launch + daysElapsed * day
        )
    }

    func testRequestsWhenSavedEnoughAndUsedLongEnough() {
        XCTAssertTrue(shouldRequest(itemCount: 10, daysElapsed: 3))
        XCTAssertTrue(shouldRequest(itemCount: 40, daysElapsed: 90))
    }

    func testTooFewItems() {
        XCTAssertFalse(shouldRequest(itemCount: 9, daysElapsed: 30))
        XCTAssertFalse(shouldRequest(itemCount: 0, daysElapsed: 30))
    }

    /// 入れた初日に大量に流し込んだ人には出さない
    func testTooSoonEvenWithManyItems() {
        XCTAssertFalse(shouldRequest(itemCount: 100, daysElapsed: 0))
        XCTAssertFalse(shouldRequest(itemCount: 100, daysElapsed: 2))
    }

    func testNeverAsksTwice() {
        XCTAssertFalse(shouldRequest(itemCount: 100, daysElapsed: 90, alreadyRequested: true))
    }

    /// 端末の時計が巻き戻っても、経過日数が負のまま条件を通さない
    func testClockGoingBackwards() {
        XCTAssertFalse(shouldRequest(itemCount: 100, daysElapsed: -10))
    }
}
