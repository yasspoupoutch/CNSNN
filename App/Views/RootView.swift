import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        Group {
            if state.progress.username.isEmpty { OnboardingView() }
            else {
                TabView {
                    NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house.fill") }
                    NavigationStack { StatsView() }.tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                    NavigationStack { ProfileView() }.tabItem { Label("Profil", systemImage: "person.crop.circle") }
                }
            }
        }.background(CNSNNTheme.background)
            .alert("CNSNN", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
                Button("Compris", role: .cancel) { state.error = nil }
            } message: { Text(state.error ?? "") }
    }
}
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var username = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("CNSNN").font(.system(.largeTitle, design: .rounded).weight(.black)).tracking(5)
                Spacer(minLength: 40)
                Text("Moins de lettres.\nPlus de déclics.").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                VStack(alignment: .leading, spacing: 14) {
                    Text("CHCLT").font(.system(.largeTitle, design: .monospaced).weight(.bold)).foregroundStyle(CNSNNTheme.accent)
                    Label("Chocolat. Tu as compris.", systemImage: "sparkle").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).cnsnnSurface()
                Text("Les voyelles disparaissent. À toi de retrouver le mot. Un défi par jour, ou autant de parties que tu veux.").foregroundStyle(.secondary)
                TextField("Choisis ton pseudo", text: $username).textContentType(.nickname)
                    .autocorrectionDisabled().padding(20).background(CNSNNTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel("Pseudo, entre 2 et 20 caractères")
                CNSNNButton(title: state.isBusy ? "Un instant…" : "C’est parti") { Task { await state.start(username: username) } }
                    .disabled(state.isBusy || !(2...20).contains(username.trimmingCharacters(in: .whitespacesAndNewlines).count))
                Text("Pas d’email. Pas de mot de passe. Juste jouer.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively).background(CNSNNTheme.background)
    }
}
