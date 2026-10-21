import XCTest
@testable import CNSNN

/// The rating prompt waits for the third found daily word and comes back only with a new version.
final class ReviewPromptTests: XCTestCase {
    private var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "cnsnn.review.tests")
        defaults.removePersistentDomain(forName: "cnsnn.review.tests")
    }

    func testWaitsForThirdDailyWinThenOncePerVersion() {
        XCTAssertFalse(ReviewPrompt.isDue(dailyWins: 2, version: "1.1", defaults: defaults))
        XCTAssertTrue(ReviewPrompt.isDue(dailyWins: 3, version: "1.1", defaults: defaults))
        ReviewPrompt.markAsked(version: "1.1", defaults: defaults)
        XCTAssertFalse(ReviewPrompt.isDue(dailyWins: 9, version: "1.1", defaults: defaults))
        XCTAssertTrue(ReviewPrompt.isDue(dailyWins: 9, version: "1.2", defaults: defaults))
    }

    func testNeverDuringTests() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(dailyWins: 10, version: "9.9", defaults: defaults))
    }
}
