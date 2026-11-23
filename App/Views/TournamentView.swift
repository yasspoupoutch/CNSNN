import SwiftUI
import CNSNNCore

// Tournoi de la semaine (Core/Tournament.swift): sign up until Monday 9 h, then one knockout round a day.
// This screen shows my match of the day, next week's sign-ups and the whole bracket.

enum TournamentText {
    /// "lundi 9 h", "mardi 9 h 30": in the phone's time zone.
    static func day(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = Calendar.current.component(.minute, from: date) == 0 ? "EEEE H' h'" : "EEEE H' h 'mm"
        return f.string(from: date)
    }
    static func name(_ slot: TournamentBracket.Slot) -> String {
        switch slot {
        case .player(let p): p.name
        case .empty: "personne"
        case .pending: "à venir"
        }
    }
    /// "Gagnant de Léa / Sam" in a sentence: "le gagnant de Léa / Sam".
    static func lower(_ name: String) -> String { name.hasPrefix("Gagnant") ? "le g" + name.dropFirst() : name }
}

struct TournamentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var playing: Int?
    @State private var confirmWithdraw = false

    var body: some View {
        let store = state.tournament
        ZStack {
            AmbientBackground(dimmed: false)
            VStack(spacing: 0) {
                HStack {
                    CircleIconButton(symbol: "xmark", label: "Fermer") { dismiss() }
                    Spacer()
                }
                .overlay { Text("Tournoi de la semaine").scaledFont(16, .semibold).accessibilityAddTraits(.isHeader) }
                .frame(minHeight: 48).padding(.horizontal, 16)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            mine(store)
                            signUp(store)
                            bracket(store)
                            if let message = store.message { Text(message).scaledFont(13).foregroundStyle(Palette.red) }
                        }.padding(.horizontal, 20).padding(.vertical, 12).readableWidth()
                    }
                    .scrollIndicators(.hidden)
                    .refreshable { await store.refresh(state: state, force: true) }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            await store.refresh(state: state)
            await store.loadBracket(state: state)
        }
        .fullScreenCover(item: Binding(get: { playing.map { PlayRound(round: $0) } }, set: { playing = $0?.round }),
                         onDismiss: { Task { await store.loadBracket(state: state, force: true) } }) { item in
            TournamentPlayView(week: store.currentWeek, round: item.round)
        }
        .confirmationDialog("Se désinscrire ?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Se désinscrire", role: .destructive) { Task { await store.withdraw(state: state) } }
            Button("Rester inscrit", role: .cancel) {}
        }
    }

    private struct PlayRound: Identifiable { let round: Int; var id: Int { round } }

    // MARK: My match

    @ViewBuilder private func mine(_ store: TournamentStore) -> some View {
        if let uid = state.uid ?? store.demoUID, store.currentLoaded, store.currentMine {
            let bracket = store.bracket
            let total = bracket.rounds.count
            VStack(alignment: .leading, spacing: 10) {
                switch bracket.standing(of: uid, nowMs: store.nowMs) {
                case .out:
                    Text("Le tableau de cette semaine est complet (64 joueurs).").scaledFont(15)
                case .match(let round, let match):
                    SectionKicker(text: TournamentFormat.roundName(round, of: total), color: Palette.duelText)
                    matchCard(store, uid: uid, round: round, match: match, total: total)
                case .through(let round):
                    SectionKicker(text: TournamentFormat.roundName(round, of: total), color: Palette.duelText)
                    Text("Qualifié ! Votre prochain match ouvre \(TournamentText.day(TournamentRules.roundStartMs(week: store.currentWeek, round: round + 1) ?? 0)).")
                        .scaledFont(17, .semibold)
                case .eliminated(let round):
                    SectionKicker(text: TournamentFormat.roundName(round, of: total), color: Palette.duelText)
                    Text("Éliminé cette semaine. Revanche au prochain tournoi !").scaledFont(17, .semibold)
                case .champion:
                    SectionKicker(text: "Finale", color: Palette.accent)
                    Text("Champion de la semaine 🏆").font(Typo.serifItalic(26)).foregroundStyle(Palette.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).modifier(DuelSurface(radius: 22))
        }
    }

    @ViewBuilder private func matchCard(_ store: TournamentStore, uid: String, round: Int, match: TournamentBracket.Match, total: Int) -> some View {
        let bracket = store.bracket
        let others = match.opponents(of: uid).compactMap { $0.player?.name }
        let other = others.isEmpty ? "personne" : others.joined(separator: " et ")
        let end = TournamentRules.roundEndMs(week: store.currentWeek, round: round) ?? 0
        let run = store.run(round: round, uid: uid)
        Text("Contre " + other).scaledFont(19, .bold)
        if others.count > 1 {
            Text("Match à 3 : le plus rapide des trois passe.").scaledFont(13, .semibold).foregroundStyle(Palette.duelSoft)
        }
        if match.decided {
            Text(match.winner?.uid == uid ? "Gagné ! Le tour suivant ouvre \(TournamentText.day(end))." : "Perdu…")
                .scaledFont(15, .semibold).foregroundStyle(match.winner?.uid == uid ? Palette.mint : Palette.red)
        } else if let score = run?.scoreMs {
            Text("Votre temps : " + ChallengeFormat.time(score)).scaledFont(15, .semibold)
            Text("Résultat dès que \(other) \(others.count > 1 ? "ont" : "a") joué, au plus tard \(TournamentText.day(end)).")
                .scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Text(run == nil
                 ? "5 mots, une seule partie : votre chrono démarre dès que vous commencez. Vous avez jusqu’à \(TournamentText.day(end))."
                 : "Votre partie est commencée : le chrono tourne. Finissez avant \(TournamentText.day(end)).")
                .scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Button { Haptics.selection(); playing = round } label: { Label(run == nil ? "Jouer mon match" : "Reprendre", systemImage: "play.fill") }
                .buttonStyle(DuelButtonStyle(height: 50)).frame(maxWidth: .infinity)
                .accessibilityIdentifier("tournamentPlay")
        }
        // What comes next: "Si vous gagnez : contre le gagnant de Léa / Sam".
        if match.winner == nil || match.winner?.uid == uid,
           let index = bracket.rounds[round - 1].firstIndex(of: match),
           let next = bracket.following(round: round, index: index) {
            let names = next.others.map { TournamentFormat.slotName(bracket, round: round + 1, match: next.match, position: $0) }
            Text((match.decided ? "Prochain match : contre " : "Si vous gagnez : contre ") + names.map(TournamentText.lower).joined(separator: " et "))
                .scaledFont(13, .semibold).foregroundStyle(Palette.duelText).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Next week

    private func signUp(_ store: TournamentStore) -> some View {
        let deadline = TournamentRules.deadlineMs(week: store.nextWeek).map(TournamentText.day) ?? "lundi 9 h"
        return VStack(alignment: .leading, spacing: 10) {
            SectionKicker(text: "Prochain tournoi", color: Palette.accent)
            Text(store.nextMine ? "Vous êtes inscrit. Premier match \(deadline)." : "Inscriptions ouvertes jusqu’à \(deadline).")
                .scaledFont(17, .semibold).fixedSize(horizontal: false, vertical: true)
            Text("\(store.nextCount) inscrit\(store.nextCount > 1 ? "s" : "") · 64 places · un match par jour, 24 h pour le jouer. Chaque mot passé ajoute 20 s ; à égalité, le moins d’erreurs passe.")
                .scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            if store.nextMine {
                Button("Se désinscrire") { confirmWithdraw = true }.buttonStyle(GlassPillStyle(height: 46))
            } else {
                Button { Haptics.selection(); Task { await store.signUp(state: state) } } label: { Label("S’inscrire", systemImage: "plus") }
                    .buttonStyle(DuelButtonStyle(height: 46)).frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).modifier(DuelSurface(radius: 22))
    }

    // MARK: Bracket

    @ViewBuilder private func bracket(_ store: TournamentStore) -> some View {
        if store.currentLoaded {
            let bracket = store.bracket
            if bracket.players.count < 2 {
                Text(bracket.players.isEmpty ? "Pas de tournoi cette semaine : inscrivez-vous au prochain !" : "Un seul inscrit cette semaine : pas de tournoi. Rendez-vous au prochain !")
                    .scaledFont(14).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Résultats au fil de la journée : les temps s’affichent quand le match est fini.")
                    .scaledFont(12).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
                TournamentTree(bracket: bracket, store: store, me: state.uid ?? store.demoUID)
                    .padding(.horizontal, -20)
            }
        } else if store.loading {
            ProgressView().tint(Palette.secondary).frame(maxWidth: .infinity)
        }
    }

}

/// The bracket drawn like a football one (TournamentLayout): the first rounds on both sides, the final
/// in the middle under the trophy, lines from each match to the next. It scrolls sideways and opens on
/// my match. Each player: the winner in mint with a tick, the others struck through, the times once a
/// match is over; during the day, a tick for who has played and "en jeu" for who is playing.
struct TournamentTree: View {
    let bracket: TournamentBracket
    let store: TournamentStore
    let me: String?

    static let cardWidth: CGFloat = 136
    static let columnGap: CGFloat = 28
    static let slotHeight: CGFloat = 26
    static let pad: CGFloat = 7
    static let gap: CGFloat = 14
    static let header: CGFloat = 34
    static let trophy: CGFloat = 78
    static let margin: CGFloat = 20

    static func height(_ slots: Int) -> CGFloat { pad * 2 + CGFloat(slots) * slotHeight }
    static func x(_ column: Int) -> CGFloat { margin + CGFloat(column) * (cardWidth + columnGap) }

    var body: some View {
        let layout = TournamentLayout(bracket, height: { Double(Self.height($0)) }, gap: Double(Self.gap))
        let total = bracket.rounds.count
        let width = Self.x(layout.columns) - Self.columnGap + Self.margin
        let top = Self.header + Self.trophy
        let height = top + CGFloat(layout.height) + 8
        let target = me.flatMap { uid in layout.nodes.last { bracket.rounds[$0.round - 1][$0.index].has(uid) } }
            ?? layout.node(round: total, index: 0)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    lines(layout, top: top).frame(width: width, height: height)
                    ForEach(0..<layout.columns, id: \.self) { column in
                        let round = column < total ? column + 1 : layout.columns - column
                        Text(Self.shortName(round, of: total).uppercased())
                            .scaledFont(11, .bold).tracking(1.1)
                            .foregroundStyle(round == total ? Palette.accent : Palette.tertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: Self.cardWidth)
                            .padding(.leading, Self.x(column)).padding(.top, 8)
                    }
                    if let final = layout.node(round: total, index: 0) {
                        trophy(bracket.champion)
                            .frame(width: Self.cardWidth, height: Self.trophy - 8)
                            .padding(.leading, Self.x(final.column))
                            .padding(.top, top + CGFloat(final.y) - CGFloat(final.height) / 2 - Self.trophy + 4)
                    }
                    ForEach(Array(layout.nodes.enumerated()), id: \.offset) { _, node in
                        card(bracket.rounds[node.round - 1][node.index], round: node.round, final: node.round == total)
                            .frame(width: Self.cardWidth, height: CGFloat(node.height))
                            .id("r\(node.round)m\(node.index)")
                            .padding(.leading, Self.x(node.column))
                            .padding(.top, top + CGFloat(node.y) - CGFloat(node.height) / 2)
                    }
                }
                .frame(width: width, height: height, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard let target else { return }
                DispatchQueue.main.async { proxy.scrollTo("r\(target.round)m\(target.index)", anchor: .center) }
            }
        }
        .accessibilityIdentifier("tournamentTree")
    }

    /// "Finale", "Demies", "Quarts", "8es", "16es", "Tour 1".
    static func shortName(_ round: Int, of total: Int) -> String {
        switch total - round {
        case 0: "Finale"
        case 1: "Demies"
        case 2: "Quarts"
        case 3: "8es"
        case 4: "16es"
        default: "Tour \(round)"
        }
    }

    /// The trophy above the final: the champion's crown and name once it is won.
    private func trophy(_ champion: TournamentPlayer?) -> some View {
        VStack(spacing: 4) {
            Image(systemName: champion == nil ? "trophy.fill" : "crown.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Palette.accentTop, Palette.accentBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: Palette.accent.opacity(0.55), radius: 10)
            Text(champion?.name ?? "Vainqueur ?").scaledFont(13, .bold)
                .foregroundStyle(champion == nil ? Palette.tertiary : Palette.accent).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(champion.map { "Champion : " + $0.name } ?? "Le vainqueur n’est pas encore connu")
    }

    /// The lines from each match to the next one: into the slot its winner takes, lit once it is known.
    private func lines(_ layout: TournamentLayout, top: CGFloat) -> some View {
        Canvas { context, _ in
            for node in layout.nodes where node.round > 1 {
                let match = bracket.rounds[node.round - 1][node.index]
                let parentTop = top + CGFloat(node.y) - CGFloat(node.height) / 2
                for (position, source) in match.from.enumerated() {
                    guard let child = layout.node(round: node.round - 1, index: source) else { continue }
                    let fromLeft = node.side == .left || (node.side == .center && child.side == .left)
                    let childEdge = fromLeft ? Self.x(child.column) + Self.cardWidth : Self.x(child.column)
                    let parentEdge = fromLeft ? Self.x(node.column) : Self.x(node.column) + Self.cardWidth
                    let mid = (childEdge + parentEdge) / 2
                    let childY = top + CGFloat(child.y)
                    let slotY = parentTop + Self.pad + Self.slotHeight * (CGFloat(position) + 0.5)
                    var path = Path()
                    path.move(to: CGPoint(x: childEdge, y: childY))
                    path.addLine(to: CGPoint(x: mid, y: childY))
                    path.addLine(to: CGPoint(x: mid, y: slotY))
                    path.addLine(to: CGPoint(x: parentEdge, y: slotY))
                    let before = bracket.rounds[node.round - 2][source]
                    let lit = before.decided && before.winner != nil
                    context.stroke(path, with: .color(lit ? Palette.mint.opacity(0.75) : Color.white.opacity(0.16)),
                                   style: StrokeStyle(lineWidth: lit ? 2 : 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func card(_ match: TournamentBracket.Match, round: Int, final: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let mine = me.map(match.has) ?? false
        return VStack(spacing: 0) {
            ForEach(Array(match.slots.enumerated()), id: \.offset) { _, slot in
                slotLine(match, round: round, slot: slot).frame(height: Self.slotHeight)
            }
        }
        .padding(.vertical, Self.pad).padding(.horizontal, 10)
        .background(shape.fill(LinearGradient(colors: [Palette.duel.opacity(mine ? 0.34 : 0.2), Color.white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .background(shape.fill(Palette.surface.opacity(0.92)))
        .overlay(shape.strokeBorder(final ? Palette.accent.opacity(0.8) : mine ? Palette.duelText.opacity(0.9) : Color.white.opacity(0.12), lineWidth: final || mine ? 1.5 : 1))
        .shadow(color: final ? Palette.accent.opacity(0.25) : .clear, radius: 10)
        .accessibilityElement(children: .combine)
    }

    private func slotLine(_ match: TournamentBracket.Match, round: Int, slot: TournamentBracket.Slot) -> some View {
        let player = slot.player
        let won = match.decided && player != nil && match.winner?.uid == player?.uid
        let lost = match.decided && player != nil && !won
        let mine = player != nil && player?.uid == me
        let run = player.flatMap { store.run(round: round, uid: $0.uid) }
        let opened = (TournamentRules.roundStartMs(week: store.currentWeek, round: round) ?? 0) <= store.nowMs
        let status: String = {
            guard player != nil else { return "" }
            if match.decided { return run?.scoreMs.map(ChallengeFormat.time) ?? "—" }
            guard opened else { return "" }
            if run?.finishedMs != nil { return "✓" }
            return run != nil ? "en jeu" : ""
        }()
        let name: String = switch slot {
        case .player(let p): p.name
        case .empty: "personne"
        case .pending: "…"
        }
        return HStack(spacing: 4) {
            Text(name)
                .scaledFont(13, won || mine ? .bold : .medium)
                .strikethrough(lost, color: Palette.tertiary)
                .foregroundStyle(player == nil || lost ? Palette.tertiary : won ? Palette.mint : mine ? Palette.duelText : Palette.foreground)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            if won { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.mint) }
            Text(status).scaledFont(11, status == "✓" ? .bold : .regular).monospacedDigit()
                .foregroundStyle(status == "✓" ? Palette.mint : Palette.tertiary).lineLimit(1).fixedSize()
        }
    }
}

/// One match: the start screen, then the 5 words with my clock, then my time.
struct TournamentPlayView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: TournamentPlaySession
    @State private var shakes: CGFloat = 0
    @State private var showPassed = false
    @State private var confirmQuit = false

    init(week: String, round: Int) { _session = State(initialValue: TournamentPlaySession(week: week, round: round)) }

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: session.phase == .playing)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(spacing: 0) {
                    topBar
                    content
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task { await session.resume(state: state) }
        .onChange(of: session.mistakeTick) { _, _ in
            withAnimation(reduceMotion ? nil : .linear(duration: 0.42)) { shakes += 1 }
            AccessibilityNotification.Announcement("Ce n’est pas le mot").post()
        }
        .onChange(of: session.passedTick) { _, tick in
            guard let word = session.passed else { return }
            showPassed = true
            AccessibilityNotification.Announcement("C’était " + word).post()
            Task { try? await Task.sleep(for: .seconds(2)); if session.passedTick == tick { showPassed = false } }
        }
        .confirmationDialog("Quitter le match ?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quitter", role: .destructive) { dismiss() }
            Button("Continuer à jouer", role: .cancel) {}
        } message: { Text("Votre chrono continue de tourner : revenez vite finir vos mots.") }
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Quitter") { if session.phase == .playing { confirmQuit = true } else { dismiss() } }
            Spacer()
            if session.phase == .playing, let game = session.game {
                let ms = game.scoreMs(elapsed: session.elapsedMs)
                Text(ChallengeFormat.time(ms)).scaledFont(14, .bold).monospacedDigit()
                    .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
                    .accessibilityLabel("Chrono : " + ChallengeFormat.time(ms))
            }
        }
        .overlay { Text("Match du tournoi").scaledFont(16, .semibold).accessibilityAddTraits(.isHeader) }
        .frame(minHeight: 48)
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .ready:
            centered {
                Image(systemName: "trophy.fill").font(.system(size: 54)).foregroundStyle(Palette.accent)
                Text("Prêt pour votre match ?").scaledFont(22, .bold).padding(.top, 16)
                line("5 mots, une seule partie. Le chrono démarre dès que vous appuyez et continue même si vous quittez. Chaque mot passé ajoute 20 s.")
                if session.nowMs < session.endMs {
                    Button { Haptics.selection(); Task { await session.start(state: state) } } label: { Label("C’est parti", systemImage: "play.fill") }
                        .buttonStyle(DuelButtonStyle(height: 54)).padding(.top, 24).padding(.horizontal, 30)
                        .accessibilityIdentifier("tournamentGo")
                } else {
                    line("Ce tour est terminé.")
                }
            }
        case .starting:
            centered { ProgressView().tint(Palette.secondary) }
        case .playing:
            if let game = session.game {
                if session.nowMs >= session.endMs {
                    centered { line("Le tour est terminé : ce match n’a pas été fini à temps.") }
                } else {
                    WordsBoard(game: game, answer: session.answer, answerWrong: session.answerWrong, cursor: session.cursor,
                               passed: session.passed, showPassed: showPassed, shakes: shakes,
                               press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor,
                               placeCursor: session.placeCursor, skip: { session.skip(state: state) }, submit: { session.submit(state: state) })
                }
            }
        case .sending:
            centered { ProgressView().tint(Palette.secondary); line("Envoi de votre temps…") }
        case .done:
            centered {
                Text("Votre temps").scaledFont(14).foregroundStyle(Palette.tertiary)
                Text(session.run?.scoreMs.map(ChallengeFormat.time) ?? "—").font(.system(size: 64, weight: .heavy)).monospacedDigit()
                if let missed = session.game?.missed, !missed.isEmpty {
                    line((missed.count > 1 ? "Les réponses manquées : " : "La réponse manquée : ") + missed.map { "« \($0) »" }.joined(separator: ", ") + ".")
                }
                line("Le temps officiel est mesuré par le serveur. Le résultat s’affiche dès que votre adversaire a joué, au plus tard \(TournamentText.day(session.endMs)).")
                Button("Terminer") { dismiss() }.buttonStyle(PrimaryPillStyle(height: 54)).padding(.top, 24).padding(.horizontal, 30)
            }
        case .failed(let text):
            centered {
                Text(text).scaledFont(16).multilineTextAlignment(.center).foregroundStyle(Palette.secondary).padding(.horizontal, 20)
                Button("Réessayer") {
                    Task { if session.game?.finished == true { await session.finish(state: state) } else { await session.start(state: state) } }
                }.buttonStyle(GlassPillStyle(height: 50)).padding(.top, 20).padding(.horizontal, 40)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        VStack(spacing: 0) { Spacer(); inner(); Spacer() }.frame(maxWidth: .infinity)
    }
    private func line(_ text: String) -> some View {
        Text(text).scaledFont(14).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 24).padding(.top, 10)
    }
}
