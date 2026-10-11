import SwiftUI

@main struct CNSNNApp: App {
    @State private var state: AppState
    init() {
        // Configure Firebase first so AppState can see a signed-in user on the very first frame.
        if !RuntimeFlags.isTesting { FirebaseRepository.configureIfPresent() }
        _state = State(initialValue: AppState())
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(state).preferredColorScheme(.dark)
                .tint(CNSNNTheme.accent).task { await state.connectIfConfigured() }
        }
    }
}
