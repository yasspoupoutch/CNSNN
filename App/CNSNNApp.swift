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
                // A challenge link (cnsnn://d/CODE, opened from the web page): join it from the challenge sheet.
                .onOpenURL { url in
                    if let code = ChallengeInvite.code(in: url.absoluteString) { state.inviteCode = code }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // A new day may have started: refresh the widget and the next reminders.
            // Another device may have saved games meanwhile: merge them in.
            if phase == .active { state.refreshGlance(force: true); Task { await state.syncProgress() } }
            if phase == .background { ChallengeWatch.schedule() }
        }
        // Friend challenges: a short check when iOS grants a background refresh (see ChallengeWatch).
        .backgroundTask(.appRefresh(ChallengeWatch.identifier)) { await ChallengeWatch.run() }
    }
}
