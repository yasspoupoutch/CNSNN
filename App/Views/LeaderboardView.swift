import SwiftUI
import CNSNNCore

/// Real rankings from Firestore: today's Mot du jour by time, and all-time points and best times.
struct LeaderboardView: View {
    @Environment(AppState.self) private var state
    enum Board: String, CaseIterable, Identifiable {
        case today = "Aujourd’hui", points = "Points", fastest = "Records"
        var id: String { rawValue }
    }
    /// Bumped by the Stats page's pull to refresh.
    var refreshToken = 0
    @State private var board: Board = .today
    @State private var today: [DailyRank] = []
    @State private var players: [LeaderboardEntry] = []
    @State private var fastest: [LeaderboardEntry] = []
    @State private var myRank: (rank: Int, players: Int)?
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.uid == nil {
                Text(state.cloud == nil ? "Le classement apparaîtra quand le serveur sera configuré." : "Connectez-vous à Internet pour voir le classement.")
                    .scaledFont(15).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 24, padding: 18)
            } else {
                summary
                HStack(spacing: 8) {
                    ForEach(Board.allCases) { item in Chip(title: item.rawValue, selected: board == item) { board = item } }
                }
                list
            }
        }
        .task(id: refreshKey) { await refresh() }
    }

    @ViewBuilder private var summary: some View {
        if let entry = state.official {
            HStack(spacing: 12) {
                stat(myRank.map { Format.ordinal($0.rank) } ?? "—", myRank.map { "sur \(Format.number($0.players)) joueurs" } ?? "Rang")
                stat(Format.number(entry.points), "points officiels")
                stat("\(entry.currentStreak())", "série en cours")
            }
        } else {
            Text("Jouez le Mot du jour pour entrer au classement.")
                .scaledFont(15).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 24, padding: 18)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).scaledFont(24, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(12).foregroundStyle(Palette.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .glassPanel(radius: 22, padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var list: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            if rows.isEmpty {
                HStack {
                    if loading { ProgressView().tint(Palette.secondary) }
                    Text(loading ? "Chargement…" : (failed ? "Classement indisponible hors connexion." : emptyText))
                        .scaledFont(14).foregroundStyle(Palette.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let mine = row.id == state.uid
                if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                HStack(spacing: 12) {
                    Text(Format.ordinal(index + 1)).scaledFont(14, .bold).monospacedDigit()
                        .foregroundStyle(index < 3 ? Palette.foreground : Palette.tertiary).frame(minWidth: 34, alignment: .leading)
                    AvatarView(name: row.name, colorIndex: row.color, size: 32)
                    Text(row.name).scaledFont(15, mine ? .bold : .medium).lineLimit(1)
                    if mine { Text("vous").scaledFont(11, .semibold).foregroundStyle(Palette.secondary) }
                    Spacer(minLength: 8)
                    Text(row.value).scaledFont(15, .semibold).monospacedDigit()
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(mine ? Palette.fill1 : .clear)
                .accessibilityElement(children: .combine)
            }
        }.glassPanel(radius: 24, padding: 0)
    }

    private var refreshKey: String { (state.uid ?? "") + "-" + String(refreshToken) }

    private var emptyText: String {
        switch board {
        case .today: "Personne n’a encore trouvé le mot du jour."
        case .points, .fastest: "Aucun résultat pour le moment."
        }
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let value: String
        /// Stable across launches, unlike hashValue.
        var color: Int { id.unicodeScalars.reduce(0) { $0 + Int($1.value) } }
    }
    private var rows: [Row] {
        switch board {
        case .today: today.map { Row(id: $0.uid, name: $0.username, value: Format.clock($0.timeMs) + ($0.usedHint ? " · indice" : "")) }
        case .points: players.map { Row(id: $0.uid, name: $0.username, value: Format.number($0.points) + " pts") }
        case .fastest: fastest.map { Row(id: $0.uid, name: $0.username, value: Format.seconds($0.bestTimeMs)) }
        }
    }

    private func refresh() async {
        guard let cloud = state.cloud, state.uid != nil else { return }
        loading = true; failed = false
        defer { loading = false }
        await state.refreshOfficial()
        do {
            today = try await cloud.dailyRanking(day: DailySchedule.key())
            players = try await cloud.topPlayers()
            fastest = try await cloud.fastestPlayers()
            if let entry = state.official { myRank = try await cloud.rank(points: entry.points) }
        } catch { failed = true }
    }
}
