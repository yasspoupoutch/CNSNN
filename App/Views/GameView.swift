import SwiftUI
import CNSNNCore

struct GameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = GameSession()
    @FocusState private var focused: Bool
    @State private var confirmSkip = false
    @State private var reporting = false
    @State private var reportReason = ""
    let mode: GameMode
    var category: CNSNNCore.Category? = nil
    var difficulty: Difficulty? = nil
    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let result = session.result {
                    resultView(result).transition(.opacity)
                } else if let card = session.card {
                    HStack {
                        GlassCapsule(text: card.category.rawValue, symbol: "square.grid.2x2")
                        Spacer()
                    }
                    Text(card.difficulty.rawValue.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Quel est ce mot ?").foregroundStyle(.secondary)
                        Text(card.wordNoVowels).font(.system(.largeTitle, design: .monospaced).weight(.bold))
                            .tracking(4).foregroundStyle(CNSNNTheme.accent).fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Consonnes : " + card.wordNoVowels.map(String.init).joined(separator: ", "))
                        if session.usedHint { Text(card.hint).foregroundStyle(.secondary).transition(.opacity) }
                    }.frame(maxWidth: .infinity, alignment: .leading).cnsnnSurface()
                    AnswerField(answer: $session.answer) { submit() }.focused($focused)
                    if let feedback = session.feedback { Text(feedback).font(.subheadline).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
                    CNSNNButton(title: "Valider", symbol: "checkmark") { submit() }.disabled(WordEngine.normalize(session.answer).isEmpty)
                    HStack {
                        Button(session.usedHint ? "Indice révélé · points ÷ 2" : "Un indice") {
                            Haptics.selection()
                            withAnimation(reduceMotion ? nil : CNSNNTheme.spring) { session.usedHint = true }
                        }.disabled(session.usedHint)
                        Spacer()
                        Button("Passer") { confirmSkip = true }
                    }.font(.subheadline).buttonStyle(.bordered).controlSize(.large)
                    Text(mode == .daily ? "Un essai quotidien enregistré. Les erreurs ne terminent pas la partie." : "Prends ton temps. Le chrono reste discret.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Aucune carte", systemImage: "square.stack", description: Text("Aucune carte disponible pour ces filtres. Reviens en arrière pour les modifier."))
                }
            }.padding(24)
                .animation(reduceMotion ? nil : CNSNNTheme.spring, value: session.result?.id)
        }.background(CNSNNTheme.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(mode == .daily ? "Mot du jour" : "Classique").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if state.cloud != nil, let card = session.card, !card.id.hasPrefix("seed-") {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Signaler", systemImage: "flag") { reporting = true }.accessibilityLabel("Signaler cette carte")
                    }
                }
            }
            .alert("Signaler la carte", isPresented: $reporting) {
                TextField("Pourquoi ? (5 à 300 caractères)", text: $reportReason)
                Button("Envoyer") {
                    guard let card = session.card else { return }
                    Task {
                        do { try await state.cloud?.report(cardID: card.id, reason: reportReason); reportReason = "" }
                        catch { state.error = error.localizedDescription }
                    }
                }.disabled(!(5...300).contains(reportReason.count))
                Button("Annuler", role: .cancel) {}
            }
            .task { if session.card == nil && session.result == nil { session.load(mode: mode, category: category, difficulty: difficulty, state: state) } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { session.resume() } else { session.pause() } }
            .confirmationDialog("Révéler le mot et terminer cette carte ?", isPresented: $confirmSkip, titleVisibility: .visible) {
                Button("Révéler le mot", role: .destructive) { focused = false; session.finish(correct: false, mode: mode, state: state) }
            }
    }
    private func submit() {
        session.submit(mode: mode, state: state)
        if session.result != nil { focused = false }
    }
    @ViewBuilder private func resultView(_ result: Attempt) -> some View {
        Image(systemName: result.correct ? "checkmark.seal" : "lightbulb").font(.system(size: 56, weight: .light)).foregroundStyle(CNSNNTheme.accent).accessibilityHidden(true)
        Text(result.correct ? "Bien trouvé." : "Un mot à retenir.").font(.largeTitle.weight(.semibold))
        if let card = session.card { Text(card.wordFull).font(.title2).foregroundStyle(.secondary) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 12) {
            StatCard(title: mode == .daily ? "Temps total" : "Temps actif", value: String(format: "%.1f s", Double(result.timeMs) / 1000), symbol: "timer")
            StatCard(title: "Points locaux", value: "+\(result.points)", symbol: "sparkle")
        }
        if result.correct, result.timeMs == state.progress.bestTimeMs {
            Label("Ton meilleur temps", systemImage: "trophy").foregroundStyle(CNSNNTheme.accent)
        }
        if mode == .classic {
            CNSNNButton(title: "Carte suivante") { session.load(mode: mode, category: category, difficulty: difficulty, state: state) }
        } else {
            Text("Ton défi du jour est enregistré. À demain pour un nouveau déclic.").foregroundStyle(.secondary)
            Label("Classement communautaire à venir", systemImage: "person.2").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
