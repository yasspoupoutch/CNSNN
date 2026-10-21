import SwiftUI
import CNSNNCore

/// Moderator tools. The rules check the admin role on every write; hiding this screen is only comfort.
struct ModerationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [Card] = []
    @State private var reports: [CardReport] = []
    @State private var playerReports: [PlayerReport] = []
    @State private var suspended: [SuspendedPlayer] = []
    @State private var suspicious: [DailyRank] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var message: String?
    var body: some View {
        List {
            if let message { Section { Text(message) } }
            Section {
                if cards.isEmpty { Text(loaded ? "Aucune carte à examiner." : "Chargement…").foregroundStyle(.secondary) }
                ForEach($cards) { $card in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(card.wordFull).font(.headline)
                            Spacer()
                            Text(card.wordNoVowels).font(.body.monospaced()).foregroundStyle(.secondary)
                        }
                        Text("Proposée par " + (card.author ?? "un joueur inconnu")).font(.subheadline).foregroundStyle(.secondary)
                        TextField("Indice", text: $card.hint, axis: .vertical).lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Picker("Catégorie", selection: $card.category) {
                                ForEach(CNSNNCore.Category.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("Difficulté", selection: $card.difficulty) {
                                ForEach(Difficulty.allCases) { Text($0.rawValue).tag($0) }
                            }
                        }.pickerStyle(.menu)
                        HStack {
                            Button("Approuver") { review(card, true) }.buttonStyle(.borderedProminent)
                                .disabled(!(5...160).contains(card.hint.trimmingCharacters(in: .whitespacesAndNewlines).count))
                            Button("Refuser", role: .destructive) { review(card, false) }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }.padding(.vertical, 6)
                }
            } header: { Text("Cartes en attente") } footer: { Text("Vous pouvez corriger l’indice, la catégorie et la difficulté avant d’approuver. Le mot ne change pas.") }
            Section("Cartes signalées") {
                if reports.isEmpty { Text(loaded ? "Aucun signalement en attente." : "Chargement…").foregroundStyle(.secondary) }
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(report.word ?? report.cardID).font(.headline)
                        Text(report.reason)
                        HStack {
                            Button("Retirer la carte", role: .destructive) { act { try await state.cloud?.withdraw(report: report) } }
                                .buttonStyle(.bordered)
                            Button("Garder la carte") { act { try await state.cloud?.resolve(report: report) } }
                                .buttonStyle(.bordered)
                        }.disabled(busy)
                    }.padding(.vertical, 6)
                }
            }
            Section {
                if playerReports.isEmpty { Text(loaded ? "Aucun pseudo signalé." : "Chargement…").foregroundStyle(.secondary) }
                ForEach(playerReports) { report in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(report.username).font(.headline)
                        Text(report.reason).foregroundStyle(.secondary)
                        HStack {
                            Button("Suspendre", role: .destructive) {
                                act {
                                    try await state.cloud?.suspend(player: report.playerID, username: report.username, reason: report.reason)
                                    try await state.cloud?.resolve(playerReport: report)
                                }
                            }.buttonStyle(.bordered)
                            Button("Ignorer") { act { try await state.cloud?.resolve(playerReport: report) } }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }.padding(.vertical, 6)
                }
            } header: { Text("Pseudos signalés") } footer: { Text("Un joueur suspendu disparaît des classements et ne peut plus jouer le mot du jour classé, proposer ni signaler. Ses résultats sont conservés.") }
            Section {
                if suspicious.isEmpty { Text(loaded ? "Aucun temps suspect aujourd’hui." : "Chargement…").foregroundStyle(.secondary) }
                ForEach(suspicious) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.username)
                            Text(Format.clock(row.timeMs) + (row.wrongAnswers == 0 ? " · sans faute" : " · \(row.wrongAnswers) erreur\(row.wrongAnswers > 1 ? "s" : "")"))
                                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Suspendre", role: .destructive) {
                            act { try await state.cloud?.suspend(player: row.uid, username: row.username, reason: "Temps suspect") }
                        }.buttonStyle(.bordered).disabled(busy)
                    }
                }
            } header: { Text("Temps suspects") } footer: { Text("Mots du jour trouvés en moins de 5 secondes aujourd’hui, trop vite pour être lus et tapés à la main.") }
            Section {
                if suspended.isEmpty { Text(loaded ? "Aucun joueur suspendu." : "Chargement…").foregroundStyle(.secondary) }
                ForEach(suspended) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.username)
                            if !player.reason.isEmpty { Text(player.reason).font(.footnote).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Rétablir") { act { try await state.cloud?.unsuspend(player: player.id) } }.buttonStyle(.bordered).disabled(busy)
                    }
                }
            } header: { Text("Joueurs suspendus") } footer: { Text("Rétablir un joueur lui rend ses résultats et sa place dans les classements.") }
        }
        .navigationTitle("Modération")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func refresh() async {
        do {
            guard let cloud = state.cloud else { message = "Le serveur n’est pas configuré."; return }
            guard try await cloud.isAdmin() else { message = "Accès administrateur requis."; return }
            cards = try await cloud.pendingCards(); reports = try await cloud.pendingReports()
            playerReports = try await cloud.pendingPlayerReports(); suspended = try await cloud.suspendedPlayers()
            suspicious = try await cloud.suspiciousResults(day: DailySchedule.key())
            loaded = true
        } catch { message = CloudError.message(error) }
    }
    private func review(_ card: Card, _ approved: Bool) {
        var reviewed = card
        reviewed.hint = card.hint.trimmingCharacters(in: .whitespacesAndNewlines)
        act { try await state.cloud?.review(card: reviewed, approved: approved) }
    }
    private func act(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                try await work()
                Haptics.success()
                await refresh()
                await state.refreshCards()
                await state.refreshSubmissions()
            } catch { message = CloudError.message(error) }
        }
    }
}
