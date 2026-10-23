import XCTest
import UserNotifications
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

/// The 12h reminder is offered once to players who do not have it, and never during tests.
final class ReminderOfferTests: XCTestCase {
    private var defaults: UserDefaults!
    override func setUp() {
        defaults = UserDefaults(suiteName: "cnsnn.reminder.tests")
        defaults.removePersistentDomain(forName: "cnsnn.reminder.tests")
    }

    func testOfferedOnceToPlayersWithoutTheReminder() {
        XCTAssertTrue(ReminderOffer.isDue(defaults: defaults))
        ReminderOffer.markOffered(defaults: defaults)
        XCTAssertFalse(ReminderOffer.isDue(defaults: defaults), "Refused or accepted: never asked again")
        defaults.removePersistentDomain(forName: "cnsnn.reminder.tests")
        defaults.set(true, forKey: Reminders.enabledKey)
        XCTAssertFalse(ReminderOffer.isDue(defaults: defaults), "Already on")
    }

    func testStepFollowsTheNotificationPermission() {
        XCTAssertEqual(ReminderOffer.step(for: .notDetermined), .systemPrompt)
        XCTAssertEqual(ReminderOffer.step(for: .authorized), .askInApp)
        XCTAssertEqual(ReminderOffer.step(for: .denied), .unavailable)
    }

    func testNeverDuringTests() {
        XCTAssertFalse(ReminderOffer.shouldOffer(defaults: defaults))
    }

    func testReminderDefaultsToNoon() {
        XCTAssertEqual(Reminders.defaultMinutes, 12 * 60)
    }
}
