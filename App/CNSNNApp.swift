import SwiftUI
import CNSNNCore

@main struct CNSNNApp: App {
    @State private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    init() {
        // Configure Firebase first so AppState can see a signed-in user on the very first frame.
        if !RuntimeFlags.isTesting { FirebaseRepository.configureIfPresent() }
        _state = State(initialValue: AppState())
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(state).preferredColorScheme(.dark)
                // Above this size the glass cards stop fitting on a phone screen.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .tint(CNSNNTheme.accent).task { await state.connectIfConfigured() }
                // A challenge link (https://…/d/CODE as a universal link, or cnsnn://d/CODE from the web page) is
                // joined from the challenge sheet; a friend link (…/a/CODE) adds that friend. Both handlers set the
                // same code, so one firing twice is harmless.
                .onOpenURL { open($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { open(url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // A new day may have started: refresh the widget and the next reminders.
            // Another device may have saved games meanwhile: merge them in.
            // Rankings on screen read again too (the list shown re-reads when the version moves).
            // Anonymous attendance: counted on return, sent on leaving.
            if phase == .active { state.noteOpen(); state.refreshGlance(force: true); state.rankingsVersion += 1; Task { await state.returnToApp() } }
            if phase == .background { ChallengeWatch.schedule(); state.sendUsage() }
        }
        // Friend challenges: a short check when iOS grants a background refresh (see ChallengeWatch).
        .backgroundTask(.appRefresh(ChallengeWatch.identifier)) { await ChallengeWatch.run() }
    }
    private func open(_ url: URL) {
        if let code = FriendInvite.code(in: url.absoluteString) { state.friendInviteCode = code }
        else if let code = ChallengeInvite.code(in: url.absoluteString) { state.inviteCode = code }
    }
}
