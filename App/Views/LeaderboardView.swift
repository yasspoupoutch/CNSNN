import SwiftUI
import CNSNNCore

/// Real rankings from Firestore: today's Mot du jour by time, and all-time points and best times.
struct LeaderboardView: View {
    @Environment(AppState.self) private var state
    enum Board: String, CaseIterable, Identifiable {
        case today = "Aujourd’hui", friends = "Amis", points = "Points", fastest = "Records"
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
    @State private var message: String?
    @State private var suspending: Row?
    /// Players this iPhone chose to hide, as comma-separated ids.
    @AppStorage("hiddenPlayers") private var hiddenPlayers = ""
    private var hidden: Set<String> { Set(hiddenPlayers.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.uid == nil {
                Text(state.cloud == nil ? "Le classement apparaîtra quand le serveur sera configuré." : "Connectez-vous à Internet pour voir le classement.")
                    .scaledFont(15).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 24, padding: 18)
            } else {
                summary
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Board.allCases) { item in Chip(title: item.rawValue, selected: board == item) { board = item } }
                    }
                }.scrollIndicators(.hidden)
                if board == .friends { FriendsBoard(refreshToken: refreshToken) } else {
                    if let message { Text(message).scaledFont(13).foregroundStyle(Palette.secondary).padding(.horizontal, 4) }
                    list
                    if !hidden.isEmpty {
                        Button((hidden.count == 1 ? "1 joueur masqué" : "\(hidden.count) joueurs masqués") + " · Tout afficher") { hiddenPlayers = "" }
                            .scaledFont(13, .semibold).foregroundStyle(Palette.secondary).hitTarget().padding(.horizontal, 4)
                    }
                }
            }
        }
        .task(id: refreshKey) { await refresh() }
        .confirmationDialog("Suspendre " + (suspending?.name ?? "") + " ?", isPresented: Binding(get: { suspending != nil }, set: { if !$0 { suspending = nil } }), titleVisibility: .visible) {
            Button("Suspendre", role: .destructive) { if let row = suspending { suspend(row) } }
        } message: {
            Text("Le joueur disparaît des classements et ne peut plus jouer le mot du jour classé, proposer ni signaler. Ses résultats sont conservés : vous pourrez lever la suspension dans Modération.")
        }
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
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(row.name).scaledFont(15, mine ? .bold : .medium).lineLimit(1)
                            if mine { Text("vous").scaledFont(11, .semibold).foregroundStyle(Palette.secondary) }
                        }
                        if let detail = row.detail {
                            Text(detail).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(row.value).scaledFont(15, .semibold).monospacedDigit()
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(mine ? Palette.fill1 : .clear)
                .contentShape(Rectangle())
                .contextMenu {
                    if !mine {
                        Button { report(row) } label: { Label("Signaler ce pseudo", systemImage: "flag") }
                        Button { hiddenPlayers = (hidden.union([row.id])).sorted().joined(separator: ",") } label: { Label("Masquer ce joueur", systemImage: "eye.slash") }
                        if state.isAdmin {
                            Button(role: .destructive) { suspending = row } label: { Label("Suspendre ce joueur", systemImage: "hand.raised") }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }.glassPanel(radius: 24, padding: 0)
    }

    private var refreshKey: String { (state.uid ?? "") + "-" + String(refreshToken) }

    private var emptyText: String {
        switch board {
        case .today: "Personne n’a encore trouvé le mot du jour."
        case .points, .fastest, .friends: "Aucun résultat pour le moment."
        }
    }

    private struct Row: Identifiable {
        let id: String
        let name: String
        let value: String
        var detail: String? = nil
        /// Stable across launches, unlike hashValue.
        var color: Int { id.unicodeScalars.reduce(0) { $0 + Int($1.value) } }
    }
    private var rows: [Row] { allRows.filter { !hidden.contains($0.id) } }
    private var allRows: [Row] {
        switch board {
        case .today: today.map { Row(id: $0.uid, name: $0.username, value: Format.clock($0.timeMs),
                                     detail: Mistakes.text($0.wrongAnswers) + ($0.usedHint ? " · indice" : "")) }
        case .points: players.map { Row(id: $0.uid, name: $0.username, value: Format.number($0.points) + " pts") }
        case .fastest: fastest.map { Row(id: $0.uid, name: $0.username, value: Format.seconds($0.bestTimeMs)) }
        case .friends: []
        }
    }

    private func report(_ row: Row) {
        guard let cloud = state.cloud else { return }
        Task {
            do { try await cloud.report(player: row.id, username: row.name); message = "Merci, la modération va vérifier le pseudo de " + row.name + "."; Haptics.success() }
            catch { message = CloudError.message(error) }
        }
    }
    private func suspend(_ row: Row) {
        guard let cloud = state.cloud else { return }
        Task {
            do { try await cloud.suspend(player: row.id, username: row.name, reason: "Depuis le classement"); message = row.name + " est suspendu."; await refresh() }
            catch { message = CloudError.message(error) }
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

/// The player and the friends they added with a 6-character code, ranked on today's Mot du jour.
struct FriendsBoard: View {
    @Environment(AppState.self) private var state
    var refreshToken = 0
    @State private var code: String?
    @State private var rows: [FriendStanding] = []
    @State private var friendCode = ""
    @State private var loading = false
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            codeCard
            addCard
            board
        }
        .task(id: (state.uid ?? "") + "-" + String(refreshToken)) { await refresh() }
    }

    private var codeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Votre code ami").scaledFont(13).foregroundStyle(Palette.secondary)
                Text(code ?? "······").scaledFont(26, .bold).monospaced().tracking(3)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let code {
                ShareLink(item: "Ajoute-moi sur CNSNN pour comparer nos temps au mot du jour : mon code ami est " + code + ". " + Site.home.absoluteString) {
                    Label("Partager", systemImage: "square.and.arrow.up").scaledFont(14, .semibold)
                }.buttonStyle(GlassPillStyle(height: 44)).frame(width: 132)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 24, padding: 18)
        .accessibilityElement(children: .combine)
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Code d’un ami", text: $friendCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .scaledFont(17, .semibold).monospaced()
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Palette.fill1))
                    .onChange(of: friendCode) { _, value in
                        let clean = FirebaseRepository.normalizedFriendCode(value)
                        if clean != value { friendCode = clean }
                    }
                    .submitLabel(.done).onSubmit(add)
                Button("Ajouter", action: add).buttonStyle(PrimaryPillStyle(height: 48)).frame(width: 112)
                    .disabled(friendCode.count != 6 || busy)
            }
            if let message { Text(message).scaledFont(13).foregroundStyle(Palette.secondary) }
        }.glassPanel(radius: 24, padding: 14)
    }

    @ViewBuilder private var board: some View {
        VStack(spacing: 0) {
            if rows.count <= 1 {
                HStack {
                    if loading { ProgressView().tint(Palette.secondary) }
                    Text(loading ? "Chargement…" : (failed ? "Classement indisponible hors connexion." : "Ajoutez un ami avec son code pour comparer vos temps chaque jour."))
                        .scaledFont(14).foregroundStyle(Palette.tertiary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            if rows.count > 1 {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let mine = row.uid == state.uid
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    HStack(spacing: 12) {
                        Text(Format.ordinal(index + 1)).scaledFont(14, .bold).monospacedDigit()
                            .foregroundStyle(index < 3 ? Palette.foreground : Palette.tertiary).frame(minWidth: 34, alignment: .leading)
                        AvatarView(name: row.username, colorIndex: row.uid.unicodeScalars.reduce(0) { $0 + Int($1.value) }, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(row.username).scaledFont(15, mine ? .bold : .medium).lineLimit(1)
                                if mine { Text("vous").scaledFont(11, .semibold).foregroundStyle(Palette.secondary) }
                            }
                            Text(Format.number(row.points) + " pts" + (row.streak > 0 ? " · série \(row.streak)" : "")
                                 + (row.today?.correct == true ? " · " + Mistakes.text(row.todayWrong ?? 0) : ""))
                                .scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(todayText(row)).scaledFont(15, .semibold).monospacedDigit()
                            .foregroundStyle(row.today?.correct == true ? Palette.foreground : Palette.tertiary)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 58)
                    .background(mine ? Palette.fill1 : .clear)
                    .contentShape(Rectangle())
                    .contextMenu {
                        if !mine {
                            Button(role: .destructive) { remove(row) } label: { Label("Retirer de mes amis", systemImage: "person.badge.minus") }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }.glassPanel(radius: 24, padding: 0)
    }

    private func todayText(_ row: FriendStanding) -> String {
        guard let today = row.today else { return "pas joué" }
        return today.correct ? Format.clock(today.timeMs) : "raté"
    }

    private func refresh() async {
        guard let cloud = state.cloud, let uid = state.uid else { return }
        loading = true; failed = false
        defer { loading = false }
        let name = state.progress.username.isEmpty ? "Joueur" : state.progress.username
        do {
            if code == nil { code = try await cloud.friendCode(uid: uid, username: name) }
            rows = try await cloud.friendsBoard(uid: uid, username: name, day: DailySchedule.key())
        } catch { failed = true }
    }
    private func add() {
        guard let cloud = state.cloud, let uid = state.uid, friendCode.count == 6, !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let name = try await cloud.addFriend(code: friendCode, uid: uid)
                friendCode = ""; message = name + " fait partie de vos amis."
                Haptics.success()
                await refresh()
            } catch { message = CloudError.message(error); Haptics.retry() }
        }
    }
    private func remove(_ row: FriendStanding) {
        guard let cloud = state.cloud, let uid = state.uid else { return }
        Task {
            do { try await cloud.removeFriend(uid: uid, friend: row.uid); rows.removeAll { $0.uid == row.uid } }
            catch { message = CloudError.message(error) }
        }
    }
}

/// "sans faute", "1 erreur", "3 erreurs": wrong guesses on the day's word.
enum Mistakes {
    static func text(_ count: Int) -> String {
        switch count {
        case ...0: "sans faute"
        case 1: "1 erreur"
        default: "\(count) erreurs"
        }
    }
}
