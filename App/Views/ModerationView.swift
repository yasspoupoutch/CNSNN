import SwiftUI
import CNSNNCore

/// Moderator tools. The rules check the admin role on every write; hiding this screen is only comfort.
struct ModerationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [Card] = []
    @State private var reports: [CardReport] = []
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
            Section("Signalements") {
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
            } catch { message = CloudError.message(error) }
        }
    }
}
