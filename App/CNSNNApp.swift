import SwiftUI

@main struct CNSNNApp: App {
    @State private var state = AppState()
    init() { if !RuntimeFlags.isTesting { FirebaseRepository.configureIfPresent() } }
    var body: some Scene {
        WindowGroup {
            RootView().environment(state).preferredColorScheme(.dark)
                // Above this size the glass cards stop fitting on a phone screen.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .tint(CNSNNTheme.accent).task { await state.connectIfConfigured() }
        }
    }
}
