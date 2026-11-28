import SwiftUI
import CNSNNCore

/// Sprint, Survie and Double sens, in full screen. Same board, keyboard and glass as the other games;
/// each mode adds its own header (clock, hearts or rounds) and its results.
struct ModeGameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: ModeSession
    @State private var confirmQuit = false
    @State private var shakes: CGFloat = 0
    @State private var showPassed = false
    /// Sprint: gold vowels falling when the results show a beaten record.
    @State private var rainTick = 0
    let mode: PlayMode

    init(mode: PlayMode) {
        self.mode = mode
        _session = State(initialValue: ModeSession(mode: mode))
    }

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: !session.over)
            VStack(spacing: 0) {
                topBar
                if session.over { Spacer() } else { content }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            if session.over {
                Palette.dim.ignoresSafeArea().transition(.opacity)
                VStack {
                    Spacer()
                    ModeResultView(session: session, replay: replay, close: { dismiss() }, rain: { rainTick += 1 }).padding(.horizontal, 8)
                }.readableWidth().transition(.move(edge: .bottom))
                if rainTick > 0 { VowelRain().id(rainTick).ignoresSafeArea() }
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: session.over)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            if session.sprint == nil && session.survival == nil && session.duo == nil { session.begin(state: state) }
            guard mode == .sprint else { return }
            // The record holder for the bar (cached: at most 2 reads every 15 minutes).
            Task { await state.refreshSprintLeader() }
            // The Sprint clock: ends the game the moment the time is up.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                session.tick(state: state)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.tick(state: state) } }
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
        .confirmationDialog(quitTitle, isPresented: $confirmQuit, titleVisibility: .visible) {
            if mode != .sprint {
                Button("Reprendre plus tard") { dismiss() }
            }
            Button(mode == .sprint ? "Arrêter le sprint" : "Abandonner", role: .destructive) { session.quit(state: state) }
            Button("Continuer à jouer", role: .cancel) {}
        } message: { Text(quitMessage) }
    }

    private var quitTitle: String { mode == .sprint ? "Arrêter le sprint ?" : "Quitter la partie ?" }
    private var quitMessage: String {
        switch mode {
        case .sprint: "La partie est comptée avec votre score actuel."
        case .survival: "Vous pouvez la reprendre plus tard depuis l’accueil, ou l’abandonner : elle sera comptée telle quelle."
        case .duo: "Vous pouvez la reprendre plus tard (le chrono continue), ou l’abandonner : les manches restantes compteront comme perdues."
        }
    }

    private func replay() {
        Haptics.selection()
        rainTick = 0
        session.begin(state: state)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Quitter") {
                if session.over || session.finished { dismiss() } else { confirmQuit = true }
            }
            Spacer()
            trailing
        }
        .overlay {
            VStack(spacing: 1) {
                Text(mode.title).scaledFont(16, .semibold)
                Text(subtitle).scaledFont(12).foregroundStyle(Palette.tertiary)
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    private var subtitle: String {
        switch mode {
        case .sprint: return "90 secondes"
        case .survival: return session.resumed ? "Partie reprise" : "3 vies"
        case .duo:
            guard let duo = session.duo else { return "" }
            return "Manche \(min(duo.round + 1, duo.duos.count)) sur \(duo.duos.count)"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch mode {
        case .sprint:
            pill(Format.number(session.sprint?.found ?? 0), label: "Mots")
        case .survival:
            Hearts(lives: session.survival?.lives ?? 3, lost: session.lifeLostTick, gained: session.lifeGainedTick)
        case .duo:
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                pill(Format.clock(session.duo?.playMs(elapsed: session.elapsedMs) ?? 0), label: "Chrono")
            }
        }
    }

    private func pill(_ value: String, label: String) -> some View {
        Text(value).scaledFont(14, .bold).monospacedDigit().foregroundStyle(Palette.foreground)
            .contentTransition(.numericText())
            .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
            .accessibilityLabel("\(label) : \(value)")
    }

    // MARK: Board

    @ViewBuilder private var content: some View {
        switch mode {
        case .sprint: if let game = session.sprint { sprintBoard(game) }
        case .survival: if let game = session.survival { survivalBoard(game) }
        case .duo: if let game = session.duo { duoBoard(game) }
        }
    }

    @ViewBuilder private func sprintBoard(_ game: SprintGame) -> some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            SprintClock(remainingMs: game.remainingMs(elapsed: session.elapsedMs))
        }.padding(.top, 6)
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            SprintRecordBar(found: game.found, streak: game.streak, accuracy: game.accuracy,
                            personal: session.previous.best(ModeStat.words), leader: state.sprintLeader, me: state.uid, pulse: session.successTick,
                            ghost: session.ghostCount(elapsed: session.elapsedMs))
        }
        .padding(.top, 12)
        if let card = game.card { clue(card) }
        // Over the free space, so the board never moves.
        Spacer(minLength: 8).overlay { passedLine }
        answerLine.overlay { FlyingWord(word: session.foundWord, tick: session.successTick).padding(.horizontal, 24) }
        actions(skip: "Passer · −5 s", skipLabel: "Passer ce mot, 5 secondes de pénalité")
        LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
    }

    @ViewBuilder private func survivalBoard(_ game: SurvivalGame) -> some View {
        HStack(spacing: 8) {
            stat("\(game.found)", game.found > 1 ? "mots trouvés" : "mot trouvé")
            stat("\(game.level)", "niveau")
            stat(game.card?.difficulty.rawValue ?? "—", "difficulté")
        }.padding(.top, 10)
        Text(SurvivalGame.bonusEvery - game.found % SurvivalGame.bonusEvery == 1 ? "Encore 1 mot pour regagner une vie" : "Une vie regagnée tous les \(SurvivalGame.bonusEvery) mots")
            .scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 8)
        if let card = game.card { clue(card) }
        // Over the free space, so the board never moves.
        Spacer(minLength: 8).overlay { passedLine }
        answerLine
        actions(skip: "Passer · −1 vie", skipLabel: "Passer ce mot, une vie en moins")
        LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
    }

    @ViewBuilder private func duoBoard(_ game: DuoGame) -> some View {
        if let duo = game.duo {
            let consonants = duo.consonants
            Text(consonants)
                .font(Typo.serif(consonants.count > 4 ? 64 : 84)).tracking(4)
                .lineLimit(1).minimumScaleFactor(0.4).padding(.top, 18)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
            Text("Deux mots, les mêmes consonnes").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 2)
            VStack(spacing: 10) {
                DuoClueRow(number: 1, word: duo.first, found: game.found[game.round][0], revealed: game.roundComplete)
                DuoClueRow(number: 2, word: duo.second, found: game.found[game.round][1], revealed: game.roundComplete)
            }.padding(.top, 16)
            Spacer(minLength: 8)
            if game.roundComplete {
                Button(game.finished ? "Voir le résultat" : "Manche suivante") { Haptics.selection(); session.nextRound(state: state) }
                    .buttonStyle(PrimaryPillStyle(height: 54)).padding(.bottom, 12)
            } else {
                answerLine
                actions(skip: "Passer la manche", skipLabel: "Passer la manche et voir les mots")
                LetterKeyboard(press: session.press, delete: session.delete, clear: session.clear, moveCursor: session.moveCursor, submit: { session.submit(state: state) })
            }
        }
    }

    /// "C'était : TOURNESOL" for two seconds after a pass, so the answer is never lost.
    /// A plain capsule, not Liquid Glass: the glass showed up without its text (an empty bubble, seen
    /// again in 1.4.2), so the bubble and its text are now drawn together, as on Android.
    /// The text keeps its full height even when little room is left above the answer, or it vanished.
    private var passedLine: some View {
        ZStack {
            if showPassed, let passed = session.passed {
                Text("C’était : " + passed.uppercased())
                    .scaledFont(14, .semibold).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.4)
                    .padding(.horizontal, 14).frame(minHeight: 32)
                    .background(Capsule().fill(Palette.surface.opacity(0.92)).overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1)))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showPassed)
        .accessibilityHidden(true)
    }

    private func clue(_ card: Card) -> some View {
        VStack(spacing: 0) {
            let consonants = card.wordNoVowels
            BoardLetters(text: consonants, size: consonants.count > 5 ? 60 : 80)
                .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
                .id(card.id)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .opacity))
            Text("\(card.category.rawValue) · \(card.difficulty.rawValue)").scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 4)
            Text("« \(card.hint) »").font(Typo.serifItalic(22)).multilineTextAlignment(.center).lineSpacing(2)
                .lineLimit(3).minimumScaleFactor(0.7)
                .padding(.horizontal, 10).padding(.top, 14)
                .id("hint-" + card.id)
        }
        .padding(.top, 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: card.id)
    }

    private func stat(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).scaledFont(18, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(highlight ? Palette.mint : Palette.foreground)
                .contentTransition(.numericText())
            Text(label).scaledFont(11).foregroundStyle(Palette.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : CNSNNTheme.spring, value: value)
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if session.answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            if !session.answer.isEmpty { AnswerLetters(answer: session.answer, wrong: session.answerWrong, cursor: session.cursor, place: session.placeCursor) }
            if TypedAnswer(text: session.answer, cursor: session.cursor).inside == nil { Caret() }
        }
        .lineLimit(1).minimumScaleFactor(0.3)
        .frame(maxWidth: .infinity, minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.tertiary).frame(height: 1) }
        .padding(.horizontal, 24)
        .modifier(Shake(animatableData: shakes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Votre réponse")
        .accessibilityValue(session.answer.isEmpty ? "vide" : session.answer)
    }

    private func actions(skip: String, skipLabel: String) -> some View {
        Button { Haptics.selection(); session.skip(state: state) } label: {
            Text(skip).scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(skipLabel)
        .padding(.vertical, 10)
    }
}

// MARK: - Pieces

/// The Sprint progress: a bar of the words found, marked with the player's record and the game's record
/// (when it is within reach: at most 1.5 times the player's record). The bar starts white and warms up
/// with the streak (gold from 3 in a row, orange from 5, red-orange from 8); a mistake cools it back.
/// A halo of light turns around it from the first word, a little faster with each word in a row. A pale
/// ghost runs at the pace of the record game, and the header tells how far ahead or behind it the
/// player is. Each word makes the bar leap and flash; nothing here delays the next word. Same rules as
/// Android's SprintRecordBar.
private struct SprintRecordBar: View {
    var found: Int
    var streak: Int
    var accuracy: Int
    /// The player's best before this game (0: none yet, the bar aims at 10).
    var personal: Int
    var leader: SprintRecord?
    var me: String?
    var pulse: Int
    /// Words of the record game at this moment (nil: no record yet).
    var ghost: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false
    @State private var overtake = false

    private var goal: Int { personal > 0 ? personal : 10 }
    private var gameRecord: SprintRecord? {
        guard let leader, leader.uid != me, leader.best > personal, Double(leader.best) <= Double(goal) * 1.5 else { return nil }
        return leader
    }
    private var scale: Double { max(Double(max(goal, gameRecord?.best ?? 0)) * 1.2, Double(found) + 2, 10) }
    private var heat: Color { SprintHeat.color(streak) }
    private var streakText: String {
        streak >= 8 ? "Inarrêtable ×\(streak)" : streak >= 5 ? "Quelle série ×\(streak)" : streak >= 3 ? "Belle série ×\(streak)" : "Combo ×\(max(1, streak))"
    }
    private var lead: Int? { ghost.map { found - $0 } }
    private var leadText: String {
        guard let lead else { return "\(accuracy) % précision" }
        return lead > 0 ? "+\(lead) sur ton record" : lead < 0 ? "−\(-lead) sur ton record" : "à égalité avec ton record"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(streakText).font(streak >= 2 ? Typo.serifItalic(17) : .system(size: 12, weight: .semibold))
                    .foregroundStyle(streak >= 2 ? heat : Palette.tertiary)
                    .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy, value: streak)
                Spacer()
                Text(leadText).font(.system(size: 12, weight: (lead ?? 0) > 0 ? .bold : .regular))
                    .foregroundStyle((lead ?? 0) > 0 ? Palette.mint : Palette.tertiary)
                    .scaleEffect(overtake ? 1.2 : 1)
                    .contentTransition(.numericText())
            }
            .frame(height: 20)
            GeometryReader { geo in
                let width = geo.size.width
                let x = { (value: Int) in width * min(1, CGFloat(Double(value) / scale)) }
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fill1).overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                        if let ghost, ghost > 0 {
                            Capsule().fill(Palette.foreground.opacity(0.16))
                                .overlay(alignment: .trailing) { Capsule().fill(Palette.foreground.opacity(0.55)).frame(width: 2).padding(.vertical, 3) }
                                .frame(width: max(18, x(ghost)))
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: ghost)
                        }
                        Capsule()
                            .fill(heat)
                            .overlay(Capsule().fill(LinearGradient(colors: [.black.opacity(0.14), .white.opacity(0.22)], startPoint: .leading, endPoint: .trailing)))
                            .frame(width: max(18, x(found)))
                            .overlay(alignment: .trailing) {
                                Text("\(found)").font(.system(size: 11, weight: .heavy)).monospacedDigit().foregroundStyle(Palette.ink).padding(.trailing, 6)
                            }
                            .shadow(color: overtake ? Palette.mint.opacity(0.95) : heat.opacity(flash ? 0.95 : 0.6), radius: flash || overtake ? 14 : SprintHeat.glow(streak))
                            .brightness(flash ? 0.18 : 0)
                            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55), value: found)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.5), value: streak)
                        tick(at: x(goal))
                        if let record = gameRecord { tick(at: x(record.best)) }
                    }
                    .frame(height: 18)
                    .overlay { BarHalo(streak: streak, shown: found > 0, color: heat).allowsHitTesting(false) }
                    .scaleEffect(flash ? 1.03 : 1)
                    label(personal > 0 ? (found > personal ? "Record battu !" : "Ton record \(personal)") : "Objectif 10", done: found > personal && (personal > 0 || found >= 10), at: x(goal), width: width)
                    if let record = gameRecord {
                        label(found > record.best ? "Record du jeu : toi !" : found >= record.best - 2 ? "Plus que \(record.best - found + 1) !" : "Record du jeu · \(record.username) \(record.best)",
                              done: found >= record.best - 2, at: x(record.best), width: width)
                    }
                }
            }
            .frame(height: gameRecord == nil ? 40 : 56)
        }
        .onChange(of: pulse) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.12)) { flash = true }
            Task { try? await Task.sleep(for: .seconds(0.22)); withAnimation(.easeOut(duration: 0.3)) { flash = false } }
        }
        .onChange(of: lead ?? 0) { before, now in
            // Passing ahead of the record's ghost: a short green flash.
            guard ghost != nil, before <= 0, now > 0, !reduceMotion else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { overtake = true }
            Task { try? await Task.sleep(for: .seconds(0.35)); withAnimation(.easeOut(duration: 0.4)) { overtake = false } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(found) mot\(found > 1 ? "s" : ""), " + (personal > 0 ? "votre record : \(personal)" : "objectif : 10") + (streak >= 2 ? ", série de \(streak)" : "")
                            + (lead.map { $0 > 0 ? ", \($0) d’avance sur votre record" : $0 < 0 ? ", \(-$0) de retard sur votre record" : "" } ?? ""))
    }

    private func tick(at x: CGFloat) -> some View {
        Rectangle().fill(Palette.foreground.opacity(0.5)).frame(width: 1.5, height: 26).offset(x: x - 0.75, y: 7)
    }
    /// A label whose right edge sits on its mark (kept inside the bar's width).
    private func label(_ text: String, done: Bool, at x: CGFloat, width: CGFloat) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(done ? Palette.accent : Palette.tertiary).lineLimit(1).fixedSize()
            .frame(width: min(width, max(x + 1, 150)), alignment: .trailing)
    }
}

/// Sprint: the word just found turns gold and floats up from the answer line, fading out in 0.4 s, and
/// the line under it lights up gold. The next word is already on screen and the keyboard keeps working:
/// nothing waits for it.
private struct FlyingWord: View {
    var word: String?
    var tick: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flights: [Flight] = []
    @State private var lit = false
    struct Flight: Identifiable { let id: Int; let word: String }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(flights) { FlightText(word: $0.word).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Rectangle().fill(Palette.accent).frame(height: 1.5).opacity(lit ? 1 : 0)
                .shadow(color: Palette.accent.opacity(0.8), radius: 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: tick) { _, tick in
            guard !reduceMotion, let word else { return }
            flights.append(Flight(id: tick, word: word.uppercased()))
            lit = true
            Task { try? await Task.sleep(for: .milliseconds(60)); withAnimation(.easeOut(duration: 0.4)) { lit = false } }
            Task { try? await Task.sleep(for: .seconds(0.5)); flights.removeAll { $0.id == tick } }
        }
    }
}

private struct FlightText: View {
    var word: String
    @State private var up = false
    var body: some View {
        Text(word).tracking(4.4).scaledFont(30, .medium).foregroundStyle(Palette.accent)
            .lineLimit(1).minimumScaleFactor(0.4)
            .shadow(color: Palette.accent.opacity(0.6), radius: 8)
            .scaleEffect(up ? 0.9 : 1.12).offset(y: up ? -44 : -4).opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 0.4)) { up = true } }
    }
}

/// The bar inside the Sprint results: it fills as the score counts up, past the old record (which
/// turns gold) toward the game record when someone else holds it.
private struct ResultRecordBar: View {
    var value: Int
    var personal: Int
    var leader: SprintRecord?
    var me: String?
    var beaten: Bool
    private var other: SprintRecord? { leader.flatMap { $0.uid != me && $0.best > personal ? $0 : nil } }
    var body: some View {
        GeometryReader { geo in
            let scale = max(Double(max(personal, other?.best ?? 0, 10)) * 1.15, Double(value) + 1)
            let x = { (v: Int) in geo.size.width * CGFloat(Double(v) / scale) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Palette.fill1).frame(height: 12).offset(y: 20)
                Capsule().fill(LinearGradient(colors: beaten ? [Palette.accent, Color(red: 1, green: 0.95, blue: 0.8)] : [Palette.accentBottom, Palette.accentTop], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(12, x(value)), height: 12).offset(y: 20)
                    .shadow(color: Palette.accent.opacity(beaten ? 0.8 : 0), radius: 10)
                    .animation(.easeOut(duration: 0.12), value: value)
                if personal > 0 {
                    mark("Ton record \(personal)", at: x(personal), gold: beaten, above: false)
                }
                if let other {
                    mark("\(other.username) \(other.best)", at: x(other.best), gold: false, above: true)
                }
            }
        }
        .frame(height: 50)
        .accessibilityHidden(true)
    }
    private func mark(_ text: String, at x: CGFloat, gold: Bool, above: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Palette.foreground.opacity(0.5)).frame(width: 1.5, height: 20).offset(x: x - 0.75, y: 16)
            Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(gold ? Palette.accent : Palette.tertiary).lineLimit(1).fixedSize()
                .frame(width: 160).offset(x: x - 80, y: above ? 0 : 36)
        }
    }
}

/// Gold vowels falling over the whole screen for a beaten Sprint record (about 4 seconds).
struct VowelRain: View {
    private struct Drop { let letter: String, x: Double, size: Double, delay: Double, duration: Double, turn: Double }
    private let drops: [Drop] = (0..<46).map { index in
        Drop(letter: String(Array("AEIOU")[index % 5]), x: .random(in: 0...1), size: .random(in: 18...52),
             delay: .random(in: 0...0.9), duration: .random(in: 2.2...3.8), turn: .random(in: -270...270))
    }
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                for drop in drops {
                    let p = (time - drop.delay) / drop.duration
                    guard p > 0, p < 1 else { continue }
                    let y = -60 + (size.height + 120) * pow(p, 1.4)
                    var inner = context
                    inner.translateBy(x: drop.x * size.width, y: y)
                    inner.rotate(by: .degrees(drop.turn * p))
                    inner.opacity = 1 - 0.1 * p
                    inner.draw(Text(drop.letter).font(Typo.serif(drop.size)).foregroundStyle(Palette.accent), at: .zero)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The Sprint bar's heat: white, then pale gold (2 in a row), gold (3), orange (5), red-orange (8 and more).
enum SprintHeat {
    private static let stops: [(Int, (Double, Double, Double))] = [
        (0, (0.957, 0.961, 0.973)), (2, (1, 0.906, 0.659)), (3, (1, 0.777, 0.355)), (5, (1, 0.588, 0.235)), (8, (1, 0.376, 0.157)),
    ]
    static func color(_ streak: Int) -> Color {
        let k = max(0, streak)
        guard let upper = stops.firstIndex(where: { $0.0 >= k }), upper > 0 else {
            let last = k >= 8 ? stops[stops.count - 1].1 : stops[0].1
            return Color(red: last.0, green: last.1, blue: last.2)
        }
        let (a, b) = (stops[upper - 1], stops[upper])
        let f = Double(k - a.0) / Double(b.0 - a.0)
        return Color(red: a.1.0 + (b.1.0 - a.1.0) * f, green: a.1.1 + (b.1.1 - a.1.1) * f, blue: a.1.2 + (b.1.2 - a.1.2) * f)
    }
    /// The glow around the fill.
    static func glow(_ streak: Int) -> CGFloat { streak >= 8 ? 16 : streak >= 5 ? 11 : streak >= 3 ? 7 : 4 }
}

/// A light turning around the Sprint bar, from the first word: one turn in 6 seconds, then 18 % faster
/// with each word in a row (down to 0.6 s a turn). The angle adds up frame by frame and the speed eases
/// toward its new value, so a change never makes the light jump or blink; a mistake slows it down
/// gently. Still (no turning) with Reduce Motion.
private struct BarHalo: View {
    var streak: Int
    var shown: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = Spin()

    /// Kept between frames: the angle, the current speed and the last frame's time.
    final class Spin {
        var angle = 0.0
        var speed = 60.0
        var last: Date?
        func advance(to date: Date, target: Double) -> Double {
            let dt = last.map { min(0.05, max(0, date.timeIntervalSince($0))) } ?? 0
            last = date
            speed += (target - speed) * min(1, dt * 2.2)
            angle = (angle + speed * dt).truncatingRemainder(dividingBy: 360)
            return angle
        }
    }
    private var target: Double { 360 / max(0.6, 6 * pow(0.82, Double(max(0, streak - 1)))) }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !shown)) { timeline in
            let turn = reduceMotion ? 0 : spin.advance(to: timeline.date, target: target)
            let ring = AngularGradient(gradient: Gradient(stops: [
                .init(color: color.opacity(0), location: 0), .init(color: color.opacity(0), location: 0.55), .init(color: color, location: 0.82),
                .init(color: Color(red: 1, green: 0.97, blue: 0.86), location: 0.9), .init(color: color, location: 0.95), .init(color: color.opacity(0), location: 1),
            ]), center: .center, angle: .degrees(turn))
            ZStack {
                Capsule().strokeBorder(ring, lineWidth: 2.5).blur(radius: 6)
                Capsule().strokeBorder(ring, lineWidth: 2)
            }
            .padding(-3)
        }
        .opacity(shown ? min(1, 0.45 + Double(streak) * 0.07) : 0)
        .animation(.easeInOut(duration: 1.2), value: streak)
        .animation(.easeInOut(duration: 1.2), value: shown)
    }
}

/// The Sprint countdown: a thin bar and the seconds left. The last ten seconds turn red and beat
/// gently, with a light tap for each of the last five.
private struct SprintClock: View {
    var remainingMs: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var seconds: Int { (remainingMs + 999) / 1000 }
    private var low: Bool { remainingMs <= 10_000 }
    var body: some View {
        HStack(spacing: 12) {
            Text(Format.clock(seconds * 1000)).scaledFont(17, .bold).monospacedDigit()
                .foregroundStyle(low ? Palette.red : Palette.foreground)
                .scaleEffect(low && !reduceMotion && seconds % 2 == 0 ? 1.06 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: seconds)
                .frame(minWidth: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fill1)
                    Capsule().fill(low ? Palette.red : Palette.foreground)
                        .frame(width: geo.size.width * CGFloat(remainingMs) / CGFloat(SprintGame.durationMs))
                        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: remainingMs)
                }
            }.frame(height: 6)
        }
        .onChange(of: seconds) { _, value in if (1...5).contains(value) { Haptics.key() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Temps restant")
        .accessibilityValue("\(seconds) secondes")
    }
}

private struct Hearts: View {
    var lives: Int
    var lost: Int
    var gained: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<SurvivalGame.maxLives, id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(index < lives ? Palette.red : Palette.tertiary)
                    .symbolEffect(.bounce.down, value: reduceMotion ? 0 : lost)
                    .symbolEffect(.bounce.up, value: reduceMotion || index != lives - 1 ? 0 : gained)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 36).glassCapsule()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lives) vie\(lives > 1 ? "s" : "") sur \(SurvivalGame.maxLives)")
    }
}

/// One clue of a Double sens round, and its word once found (gold vowels) or given up (grey vowels).
private struct DuoClueRow: View {
    var number: Int
    var word: DuoWord
    var found: Bool
    var revealed: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)").scaledFont(13, .bold).foregroundStyle(found ? Palette.ink : Palette.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(found ? Palette.mint : Palette.fill2))
            VStack(alignment: .leading, spacing: 6) {
                Text(word.hint).font(Typo.serifItalic(19)).foregroundStyle(Palette.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if found || revealed {
                    RevealedWord(word: word.word, correct: found)
                } else {
                    Text("à trouver").scaledFont(12).foregroundStyle(Palette.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(found ? Palette.fill2 : Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(found ? Palette.mint.opacity(0.5) : Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Indice \(number) : \(word.hint)" + (found ? ". Trouvé : \(word.word)" : revealed ? ". Réponse : \(word.word)" : ""))
    }
}

/// The word, its vowels sliding in once it appears.
private struct RevealedWord: View {
    var word: String
    var correct: Bool
    @State private var revealed = false
    var body: some View {
        VowelReveal(word: word.uppercased(), correct: correct, revealed: revealed, maxSize: 26, width: 230)
            .frame(height: 32, alignment: .leading)
            .onAppear { revealed = true }
    }
}

// MARK: - Results

private struct ModeResultView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var session: ModeSession
    var replay: () -> Void
    var close: () -> Void
    /// Sprint: the gold vowels falling over the whole screen when the record is beaten.
    var rain: () -> Void = {}
    @State private var celebrate = false
    /// Sprint: the score while it counts up word by word (nil: the final score).
    @State private var counted: Int?
    @State private var near = false
    @State private var glow = false

    private var sprintShow: Bool { session.mode == .sprint && !reduceMotion }
    private var shownValue: Int { counted ?? mainValue }
    private var personalBefore: Int { session.previous.best(ModeStat.words) }
    /// "Plus que 3 mots pour battre Inès": the game record, when someone else holds it.
    private var nearLine: String? {
        guard session.mode == .sprint, let leader = state.sprintLeader, leader.uid != state.uid, leader.best >= mainValue else { return nil }
        let missing = leader.best - mainValue + 1
        return "Plus que \(missing) mot\(missing > 1 ? "s" : "") pour battre \(leader.username)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(kicker).font(Typo.serifItalic(24)).foregroundStyle(Palette.secondary)
            Text(Format.number(shownValue)).font(.system(size: 64, weight: .heavy)).tracking(-1.5).monospacedDigit()
                .foregroundStyle(session.mode == .sprint && celebrate ? Palette.accent : Palette.foreground)
                .shadow(color: Palette.accent.opacity(session.mode == .sprint && celebrate ? 0.45 : 0), radius: 14)
                .contentTransition(.numericText(value: Double(shownValue)))
                .padding(.top, 6)
            Text(mainLabel).scaledFont(13).foregroundStyle(Palette.tertiary)
            if session.mode == .sprint {
                ResultRecordBar(value: shownValue, personal: personalBefore, leader: state.sprintLeader, me: state.uid, beaten: celebrate)
                    .padding(.top, 14).padding(.horizontal, 6)
            }
            HStack(spacing: 10) {
                ForEach(tiles, id: \.1) { value, label in tile(value, label) }
            }.padding(.top, session.mode == .sprint ? 10 : 18)
            recordLine.padding(.top, 14)
            if let nearLine {
                Text(nearLine).font(Typo.serifItalic(21)).foregroundStyle(Palette.accent).multilineTextAlignment(.center)
                    .padding(.top, 6).opacity(near || !sprintShow ? 1 : 0)
            }
            if let missed { Text(missed).scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 8) }
            HStack(spacing: 10) {
                Button("Accueil", action: close).buttonStyle(GlassPillStyle(height: 54))
                Button("Rejouer", action: replay).buttonStyle(PrimaryPillStyle(height: 54))
                    .shadow(color: Palette.accent.opacity(glow ? 0.5 : 0), radius: glow ? 16 : 0)
            }.padding(.top, 20)
            Text("Record personnel : il ne compte pas dans les classements du mot du jour.")
                .scaledFont(11).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 12)
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .background {
            let shape = RoundedRectangle(cornerRadius: 48, style: .continuous)
            shape.fill(.ultraThinMaterial).overlay(shape.fill(LinearGradient(colors: [Palette.sheetTop, Palette.sheetBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Palette.glassShadow, radius: 30, y: -20)
        }
        .onAppear {
            if sprintShow { return }
            if session.improved(mainKey) {
                Haptics.success()
                AccessibilityNotification.Announcement("Nouveau record personnel").post()
                if !reduceMotion { withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.25)) { celebrate = true } }
            }
        }
        .task {
            guard sprintShow else { return }
            await countUp()
        }
    }

    /// Sprint: the score counts up word by word, one note each (higher and higher). Passing the old
    /// record turns it gold, plays the record notes and lets the gold vowels fall. Then the line about
    /// the game record shows and Rejouer glows. About 2 to 4 seconds; the buttons work all along.
    private func countUp() async {
        let total = mainValue, improved = session.improved(mainKey)
        counted = 0
        try? await Task.sleep(for: .seconds(0.5))
        guard total > 0 else { counted = nil; return }
        for value in 1...total {
            if Task.isCancelled { return }
            withAnimation(.snappy(duration: 0.12)) { counted = value }
            SprintSound.note(min(value, SprintSound.scale.count))
            Haptics.key()
            if improved && value == personalBefore + 1 {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { celebrate = true }
                SprintSound.record(); Haptics.success(); rain()
                AccessibilityNotification.Announcement("Nouveau record personnel").post()
                try? await Task.sleep(for: .seconds(0.7))
            }
            try? await Task.sleep(for: .seconds(value < total - 3 ? 0.11 : 0.22))
        }
        counted = nil
        if !improved && session.beaten.contains(mainKey) { Haptics.success() }
        try? await Task.sleep(for: .seconds(0.4))
        withAnimation(.easeOut(duration: 0.4)) { near = true }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { glow = true }
    }

    private var mainKey: String {
        switch session.mode { case .sprint: ModeStat.words; case .survival: ModeStat.level; case .duo: ModeStat.duo }
    }
    private var records: ModeRecords { state.progress.records(session.mode) }

    private var kicker: String {
        switch session.mode {
        case .sprint: return (session.sprint?.remainingMs(elapsed: session.elapsedMs) ?? 0) == 0 ? "Temps écoulé !" : "Sprint arrêté"
        case .survival: return (session.survival?.lives ?? 0) == 0 ? "Plus de vies…" : "Partie terminée"
        case .duo: return session.duo?.perfect == true ? "Parfait, 10 sur 10 !" : "Partie terminée"
        }
    }
    private var mainValue: Int {
        switch session.mode {
        case .sprint: return session.sprint?.found ?? 0
        case .survival: return session.survival?.level ?? 1
        case .duo: return session.duo?.solved ?? 0
        }
    }
    private var mainLabel: String {
        switch session.mode {
        case .sprint: return mainValue > 1 ? "mots trouvés en 90 s" : "mot trouvé en 90 s"
        case .survival: return "niveau atteint"
        case .duo: return mainValue > 1 ? "paires trouvées" : "paire trouvée"
        }
    }

    private var tiles: [(String, String)] {
        switch session.mode {
        case .sprint:
            guard let game = session.sprint else { return [] }
            return [("\(game.bestCombo)", "meilleur combo"), ("\(game.accuracy) %", "précision"), ("\(game.skips)", game.skips > 1 ? "passés" : "passé")]
        case .survival:
            guard let game = session.survival else { return [] }
            return [("\(game.found)", game.found > 1 ? "mots trouvés" : "mot trouvé"), ("\(game.mistakes)", game.mistakes > 1 ? "erreurs" : "erreur"), (Format.number(records.best(ModeStat.words)), "meilleur parcours")]
        case .duo:
            guard let game = session.duo else { return [] }
            return [(Format.clock(game.playMs(elapsed: session.elapsedMs)), "temps"), ("\(game.wordsFound)/\(game.duos.count * 2)", "réponses"), ("\(game.errors)", game.errors > 1 ? "erreurs" : "erreur")]
        }
    }

    /// The answers not found: the words passed, then the one the time or the last life ended on.
    private var missed: String? {
        var words: [String]
        switch session.mode {
        case .sprint:
            guard let game = session.sprint else { return nil }
            words = game.missed ?? []
            if let card = game.card, game.remainingMs(elapsed: session.elapsedMs) == 0, words.last != card.wordFull { words.append(card.wordFull) }
        case .survival:
            guard let game = session.survival else { return nil }
            words = game.missed ?? []
            if game.lives == 0, let card = game.card, words.last != card.wordFull { words.append(card.wordFull) }
        case .duo: return nil
        }
        guard !words.isEmpty else { return nil }
        return (words.count > 1 ? "Les réponses manquées : " : "La réponse manquée : ") + words.map { "« \($0) »" }.joined(separator: ", ") + "."
    }

    @ViewBuilder private var recordLine: some View {
        if session.improved(mainKey) && sprintShow && !celebrate {
            // Until the count passes the old record.
            Text("Record : \(personalBefore) mot\(personalBefore > 1 ? "s" : "")").scaledFont(14, .semibold).foregroundStyle(Palette.secondary)
        } else if session.improved(mainKey) {
            Label("Nouveau record personnel", systemImage: "trophy.fill")
                .scaledFont(15, .bold).foregroundStyle(Palette.mint)
                .scaleEffect(celebrate || reduceMotion ? 1 : 0.85).opacity(celebrate || reduceMotion ? 1 : 0.6)
                .symbolEffect(.bounce, value: celebrate)
        } else if session.beaten.contains(mainKey) {
            Label("Premier record établi", systemImage: "flag.checkered").scaledFont(14, .semibold).foregroundStyle(Palette.secondary)
        } else {
            Text("Record : " + ModeRecordText.main(session.mode, records))
                .scaledFont(14, .semibold).foregroundStyle(Palette.secondary)
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).scaledFont(20, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The main personal record of a mode, as words (no points anywhere).
enum ModeRecordText {
    static func main(_ mode: PlayMode, _ records: ModeRecords) -> String {
        switch mode {
        case .sprint:
            let words = records.best(ModeStat.words)
            return "\(words) " + (words > 1 ? "mots" : "mot")
        case .survival: return "niveau \(max(1, records.best(ModeStat.level)))"
        case .duo:
            let best = records.best(ModeStat.duo)
            guard best > 0 else { return "aucun" }
            let solved = DuoRecord.solved(best)
            return "\(solved) " + (solved > 1 ? "paires" : "paire") + " en " + Format.clock(DuoRecord.seconds(best) * 1000)
        }
    }
}
