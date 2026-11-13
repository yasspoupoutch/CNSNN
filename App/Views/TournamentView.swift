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
}

/// The tournament block of the "Défier un ami" sheet: sign-up and my match, in short.
struct TournamentBox: View {
    @Environment(AppState.self) private var state
    var open: () -> Void

    var body: some View {
        let store = state.tournament
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.accent)
                SectionKicker(text: "Tournoi de la semaine", color: Palette.accent)
            }
            Text(summary(store)).scaledFont(13).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if !store.nextMine && !store.nextWeek.isEmpty {
                    Button { Haptics.selection(); Task { await store.signUp(state: state) } } label: { Label("S’inscrire", systemImage: "plus") }
                        .buttonStyle(DuelButtonStyle(height: 46)).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tournamentSignUp")
                }
                Button { Haptics.selection(); open() } label: { Label(store.currentMine ? "Mon match" : "Voir le tableau", systemImage: "trophy") }
                    .buttonStyle(DuelButtonStyle(height: 46)).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("tournamentOpen")
            }
            if let message = store.message { Text(message).scaledFont(12).foregroundStyle(Palette.red) }
        }
        .padding(16).modifier(DuelSurface(radius: 22)).padding(.top, 6)
        .task(id: state.uid) { await store.refresh(state: state) }
    }

    private func summary(_ store: TournamentStore) -> String {
        let deadline = TournamentRules.deadlineMs(week: store.nextWeek).map(TournamentText.day) ?? "lundi 9 h"
        let count = store.nextCount == 0 ? "" : store.nextCount == 1 ? " 1 inscrit pour l’instant." : " \(store.nextCount) inscrits pour l’instant."
        if store.nextMine { return "Vous êtes inscrit au prochain tournoi : il commence \(deadline).\(count)" }
        return "Un match par jour, les mêmes 5 mots pour les deux joueurs, 24 h pour jouer : le plus rapide passe au tour suivant. Inscriptions jusqu’à \(deadline).\(count)"
    }
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
        if let uid = state.uid, store.currentLoaded, store.currentMine {
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
        let other = match.opponent(of: uid)
        let end = TournamentRules.roundEndMs(week: store.currentWeek, round: round) ?? 0
        let run = store.run(round: round, uid: uid)
        Text("Contre " + TournamentText.name(other)).scaledFont(19, .bold)
        if match.decided {
            Text(match.winner?.uid == uid ? "Gagné ! Le tour suivant ouvre \(TournamentText.day(end))." : "Perdu…")
                .scaledFont(15, .semibold).foregroundStyle(match.winner?.uid == uid ? Palette.mint : Palette.red)
            times(store, round: round, match: match)
        } else if let score = run?.scoreMs {
            Text("Votre temps : " + ChallengeFormat.time(score)).scaledFont(15, .semibold)
            Text("Résultat dès que \(TournamentText.name(other)) a joué, au plus tard \(TournamentText.day(end)).")
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
    }

    private func times(_ store: TournamentStore, round: Int, match: TournamentBracket.Match) -> some View {
        let a = match.a.player.flatMap { store.run(round: round, uid: $0.uid)?.scoreMs }
        let b = match.b.player.flatMap { store.run(round: round, uid: $0.uid)?.scoreMs }
        return Text("\(TournamentText.name(match.a)) \(a.map(ChallengeFormat.time) ?? "—") · \(TournamentText.name(match.b)) \(b.map(ChallengeFormat.time) ?? "—")")
            .scaledFont(13).monospacedDigit().foregroundStyle(Palette.secondary)
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
            let total = bracket.rounds.count
            if bracket.players.count < 2 {
                Text(bracket.players.isEmpty ? "Pas de tournoi cette semaine : inscrivez-vous au prochain !" : "Un seul inscrit cette semaine : pas de tournoi. Rendez-vous au prochain !")
                    .scaledFont(14).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                if let champion = bracket.champion {
                    Text("Champion : " + champion.name + " 🏆").scaledFont(17, .bold).foregroundStyle(Palette.accent)
                }
                ForEach(Array(bracket.rounds.enumerated()).reversed(), id: \.offset) { index, matches in
                    let round = index + 1
                    if (TournamentRules.roundStartMs(week: store.currentWeek, round: round) ?? 0) <= store.nowMs || round == 1 {
                        SectionKicker(text: TournamentFormat.roundName(round, of: total)).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(matches.enumerated()), id: \.offset) { k, match in
                                if k > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                                row(store, round: round, match: match)
                            }
                        }
                        .glassPanel(radius: 20, padding: 0)
                    }
                }
            }
        } else if store.loading {
            ProgressView().tint(Palette.secondary).frame(maxWidth: .infinity)
        }
    }

    private func row(_ store: TournamentStore, round: Int, match: TournamentBracket.Match) -> some View {
        HStack(spacing: 8) {
            side(store, round: round, slot: match.a, match: match, alignment: .leading)
            Text("vs").scaledFont(11).foregroundStyle(Palette.tertiary)
            side(store, round: round, slot: match.b, match: match, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
    private func side(_ store: TournamentStore, round: Int, slot: TournamentBracket.Slot, match: TournamentBracket.Match, alignment: HorizontalAlignment) -> some View {
        let won = match.decided && slot.player != nil && match.winner?.uid == slot.player?.uid
        let mine = slot.player?.uid == state.uid
        // Times are shown once the match is decided, so nobody knows the time to beat.
        let time = match.decided ? slot.player.flatMap { store.run(round: round, uid: $0.uid)?.scoreMs }.map(ChallengeFormat.time) : nil
        return VStack(alignment: alignment, spacing: 1) {
            Text(TournamentText.name(slot)).scaledFont(14, won || mine ? .bold : .regular)
                .foregroundStyle(slot.player == nil ? Palette.tertiary : match.decided && !won ? Palette.tertiary : mine ? Palette.duelText : Palette.foreground)
                .lineLimit(1)
            if let time { Text(time).scaledFont(11).monospacedDigit().foregroundStyle(Palette.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
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
