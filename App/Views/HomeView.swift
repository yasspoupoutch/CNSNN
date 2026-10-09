import SwiftUI
import CNSNNCore

struct HomeView: View {
    @Environment(AppState.self) private var state
    @Namespace private var transition
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CNSNNGlassGroup { ViewThatFits(in: .horizontal) {
                    HStack { GlassCapsule(text: state.progress.username, symbol: "person.crop.circle.fill"); Spacer(); GlassCapsule(text: "\(state.progress.score)", symbol: "trophy.fill") }
                    VStack(alignment: .leading) { GlassCapsule(text: state.progress.username, symbol: "person.crop.circle.fill"); GlassCapsule(text: "\(state.progress.score) points", symbol: "trophy.fill") }
                }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Un mot.\nUn déclic.").font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    Text("Fais parler les consonnes.").foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                NavigationLink { GameView(mode: .daily).modifier(CardTransition(id: "daily", namespace: transition)) } label: {
                    GameCard(title: "Mot du jour", subtitle: "1 défi quotidien", letters: "AUJOURD’HUI", symbol: "sun.max", accent: true).modifier(CardTransitionSource(id: "daily", namespace: transition))
                }.buttonStyle(PressStyle()).simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
                NavigationLink { ClassicSetupView().modifier(CardTransition(id: "classic", namespace: transition)) } label: {
                    GameCard(title: "Classique", subtitle: "Entraîne-toi sans limite", letters: "À TON RYTHME", symbol: "square.stack", accent: false).modifier(CardTransitionSource(id: "classic", namespace: transition))
                }.buttonStyle(PressStyle()).simultaneousGesture(TapGesture().onEnded { Haptics.selection() })
                Label(state.cloud == nil ? "Progression enregistrée sur cet iPhone" : "Connecté · scores locaux d’entraînement", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(CNSNNTheme.background).toolbar(.hidden, for: .navigationBar)
    }
}
struct GameCard: View {
    var title: String
    var subtitle: String
    var letters: String
    var symbol: String
    var accent: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Image(systemName: symbol).font(.title2).foregroundStyle(accent ? CNSNNTheme.accent : .white)
                Spacer()
                Image(systemName: "arrow.up.right").padding(12).cnsnnGlass(interactive: true)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(letters).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                Text(title).font(.system(.title, design: .rounded).weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).cnsnnSurface()
            .foregroundStyle(.white).accessibilityElement(children: .combine)
    }
}
struct ClassicSetupView: View {
    @State private var category: CNSNNCore.Category?
    @State private var difficulty: Difficulty?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("À toi de jouer.").font(.largeTitle.weight(.semibold))
                Text("Choisis ton terrain, ou laisse-toi surprendre.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Catégorie", selection: $category) {
                        Text("Toutes").tag(nil as CNSNNCore.Category?)
                        ForEach(CNSNNCore.Category.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Difficulté", selection: $difficulty) {
                        Text("Toutes").tag(nil as Difficulty?)
                        ForEach(Difficulty.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }.pickerStyle(.menu).cnsnnSurface()
                NavigationLink { GameView(mode: .classic, category: category, difficulty: difficulty) } label: {
                    Label("Commencer", systemImage: "arrow.right").font(.headline).frame(maxWidth: .infinity).padding(20).background(CNSNNTheme.accent, in: Capsule()).foregroundStyle(CNSNNTheme.background)
                }.buttonStyle(PressStyle())
            }.padding(24)
        }.background(CNSNNTheme.background).navigationTitle("Classique").navigationBarTitleDisplayMode(.inline)
    }
}
