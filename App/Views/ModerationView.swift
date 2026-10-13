import SwiftUI
import CNSNNCore
struct ModerationView: View {
    @Environment(AppState.self) private var state
    @State private var cards: [Card] = []
    @State private var reports: [CardReport] = []
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        List {
            if let message { Section { Text(message) } }
            Section("Cartes en attente") {
                if cards.isEmpty { Text("Aucune carte à examiner.") }
                ForEach(cards) { card in
                    VStack(alignment:.leading,spacing:12) {
                        Text(card.wordFull).font(.headline)
                        Text(card.wordNoVowels).font(.body.monospaced())
                        Text(card.hint).foregroundStyle(.secondary)
                        Text(card.category.rawValue+" · "+card.difficulty.rawValue).font(.caption)
                        HStack {
                            Button("Approuver") { review(card,true) }.buttonStyle(.borderedProminent)
                            Button("Refuser",role:.destructive) { review(card,false) }.buttonStyle(.bordered)
                        }.disabled(busy)
                    }.padding(.vertical,8)
                }
            }
            Section("Signalements") {
                if reports.isEmpty { Text("Aucun signalement en attente.") }
                ForEach(reports) { report in
                    VStack(alignment:.leading,spacing:12) {
                        Text(report.word ?? report.cardID).font(.headline); Text(report.reason)
                        Button("Retirer la carte", role: .destructive) {
                            Task {
                                do { try await state.cloud?.withdraw(report: report); await refresh() }
                                catch { message = CloudError.message(error) }
                            }
                        }.buttonStyle(.bordered)
                        Button("Marquer comme traité") {
                            Task {
                                do { try await state.cloud?.resolve(report:report); await refresh() }
                                catch { message = CloudError.message(error) }
                            }
                        }.buttonStyle(.bordered)
                    }
                }
            }
        }.navigationTitle("Modération").task { await refresh() }.refreshable { await refresh() }
    }
    private func refresh() async {
        do {
            guard let cloud = state.cloud else { return }
            guard try await cloud.isAdmin() else { message = "Accès administrateur requis."; return }
            cards = try await cloud.pendingCards(); reports = try await cloud.pendingReports()
        } catch { message = CloudError.message(error) }
    }
    private func review(_ card: Card, _ approved: Bool) {
        busy = true
        Task {
            defer { busy = false }
            do { try await state.cloud?.review(card:card,approved:approved); await refresh() }
            catch { message = CloudError.message(error) }
        }
    }
}
