import SwiftUI
import CNSNNCore

struct GameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = GameSession()
    @State private var confirmSkip = false
    /// The last hint of the Mot du jour shows the word and ends the game: asked once.
    @State private var confirmReveal = false
    @State private var reporting = false
    @State private var reportReason = ""
    @State private var shakes: CGFloat = 0
    @State private var finishedHere = false
    let mode: GameMode
    var category: CNSNNCore.Category? = nil
    var difficulty: Difficulty? = nil
    /// Rattrapage: a missed daily word of the week (mode is .daily), counted in the week with 5 minutes more.
    var catchUpDay: String? = nil
    /// First-launch tutorial: this page with an example word (TR), explained step by step. Called with
    /// true on "À vous de jouer", false on "Passer".
    var tutorial: ((Bool) -> Void)? = nil
    @State private var demo = TutorialDemo()
    /// "Un indice ?" beside the Indice button, 30 s into the Mot du jour and 30 s after the first hint.
    @State private var hintNudge = false
    /// The found word bursting into letters (and the Mot du jour place), before the result sheet.
    @State private var celebration: UUID?
    @State private var sheetShown = true

    var body: some View {
        ZStack {
            AmbientBackground(dimmed: session.result == nil)
            VStack(spacing: 0) {
                topBar
                switch session.phase {
                case .loading: loadingState
                case .failed(let message): failedState(message)
                case .playing:
                    if let card = session.card { board(card) }
                    else if session.result == nil { emptyState }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6).readableWidth()
            if let result = session.result {
                Palette.dim.ignoresSafeArea().transition(.opacity)
                if sheetShown {
                VStack {
                    Spacer()
                    ResultSheet(result: result, card: session.card, mode: mode, firstTry: finishedHere && session.wrongAnswers == 0 && session.hintsTaken == 0,
                                usedHint: session.usedHint, usedVowels: session.usedVowels, letters: session.lettersUsed, revealedWord: session.revealedWord, standing: session.standing, pending: session.pendingOfficial, ranked: session.ranked,
                                catchUp: catchUpDay != nil, next: nextCard, close: { dismiss() })
                        .padding(.horizontal, 8)
                }.readableWidth().transition(.move(edge: .bottom))
                }
            }
            if let celebration, let word = session.card?.wordFull.uppercased() {
                WordCelebration(word: word, showsRank: mode == .daily && session.ranked && catchUpDay == nil,
                                standing: { session.standing },
                                showSheet: { sheetShown = true },
                                ended: { if self.celebration == celebration { self.celebration = nil } })
                    .id(celebration)
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: session.result?.id)
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: sheetShown)
        .onChange(of: session.result?.id) { _, _ in
            // A word just found here (not one loaded from earlier, not shown by a hint): it bursts first.
            if session.result?.correct == true, session.celebrate, !reduceMotion, tutorial == nil {
                session.celebrate = false; sheetShown = false; celebration = UUID()
            } else { sheetShown = true; if session.result == nil { celebration = nil } }
        }
        // The board and keyboard share one screen, so the game caps text growth lower than the rest of the app.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .alert("Signaler la carte", isPresented: $reporting) {
            TextField("Pourquoi ? (5 à 300 caractères)", text: $reportReason)
            Button("Envoyer") {
                guard let card = session.card else { return }
                Task {
                    do {
                        try await state.cloud?.report(cardID: card.id, reason: reportReason); reportReason = ""
                        Haptics.success(); AccessibilityNotification.Announcement("Signalement envoyé").post()
                    } catch { state.error = CloudError.message(error) }
                }
            }.disabled(!(5...300).contains(reportReason.count))
            Button("Annuler", role: .cancel) {}
        }
        // In the tutorial, the real Indice moves the bubble on.
        .onChange(of: session.hintsTaken) { _, taken in if tutorial != nil && taken > 0 { demo.hintShown = true } }
        .onChange(of: session.result?.id) { _, _ in
            guard mode == .daily, catchUpDay == nil, session.result?.correct == true else { return }
            if ReminderOffer.shouldOffer() { state.reminderPending = true }
            if ReviewPrompt.shouldAsk(dailyWins: state.progress.dailyWins) { state.reviewPending = true }
        }
        .overlayPreferenceValue(TutorialAnchors.self) { anchors in
            if let tutorial {
                TutorialGameOverlay(anchors: anchors, demo: demo, finish: tutorial)
            }
        }
        .task { if tutorial != nil { session.loadTutorial(Tutorial.card) } else if session.card == nil && session.result == nil { session.load(mode: mode, category: category, difficulty: difficulty, catchUp: catchUpDay, state: state) } }
        // "Un indice ?" 30 s after the start, then again 30 s after each hint, until the word is revealed.
        .task(id: "\(session.card?.id ?? "")-\(session.hintsTaken)-\(session.hintAvailable)") {
            hintNudge = false
            guard mode == .daily, tutorial == nil, session.hintAvailable else { return }
            let firstHint = session.hintsTaken == 0
            let since = Date()
            while !Task.isCancelled, session.hintAvailable, session.result == nil {
                let waited = firstHint ? session.elapsedMs >= HintNudge.delayMs : Date().timeIntervalSince(since) * 1000 >= Double(HintNudge.delayMs)
                if session.phase == .playing, session.card != nil, waited { hintNudge = true; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.resume() } else { session.pause() } }
        .confirmationDialog("Révéler le mot et terminer cette carte ?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Révéler le mot", role: .destructive) { finishedHere = true; session.finish(correct: false, mode: mode, state: state) }
        }
        .confirmationDialog(mode == .daily ? "Afficher le mot ? La partie se termine et vous serez classé après ceux qui l’ont trouvé." : "Afficher le mot ? Il comptera comme non trouvé.", isPresented: $confirmReveal, titleVisibility: .visible) {
            Button("Afficher le mot") { finishedHere = true; session.revealHint(state: state) }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark", label: "Fermer") { dismiss() }
            Spacer()
            HStack(spacing: 8) {
                if state.cloud != nil, let card = session.card, !card.id.hasPrefix("seed-"), !card.id.hasPrefix("daily-"), !card.id.hasPrefix("secret-"), session.result == nil {
                    Button { reporting = true } label: {
                        Image(systemName: "flag").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary)
                            .frame(width: 36, height: 36).glassCapsule().hitTarget()
                    }.buttonStyle(PressStyle(scale: 0.92)).accessibilityLabel("Signaler cette carte")
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(session.phase == .playing ? Format.clock(session.result?.timeMs ?? session.elapsedMs) : "0:00")
                        .scaledFont(14, .bold).monospacedDigit().foregroundStyle(Palette.foreground)
                        .contentTransition(.numericText())
                        .padding(.horizontal, 13).frame(minHeight: 36).glassCapsule()
                        .accessibilityLabel("Chrono")
                }
                .tutorialTarget(.clock)
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text(catchUpDay.map { "Mot du " + Format.weekday($0) } ?? (mode == .daily ? "Mot du jour" : "Classique")).scaledFont(16, .semibold)
                if let card = session.card {
                    Text(card.difficulty.rawValue).scaledFont(12).foregroundStyle(Palette.tertiary)
                }
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    // MARK: Board

    @ViewBuilder private func board(_ card: Card) -> some View {
        let consonants = card.wordNoVowels
        VStack(spacing: 0) {
            if tutorial != nil {
                // The tutorial's example: the vowels slide in and out of TR.
                MorphWord(word: demo.word, from: demo.from, size: 80)
                    .id("\(demo.step)-\(demo.hintShown)")
                    .frame(minHeight: 96)
                    .padding(.top, 40)
            } else if let placed = session.placed {
                // The hints after the sentence: the word's vowels, in gold, take their places one by one.
                BoardLetters(text: placed, size: placed.count > 5 ? 64 : 88, gold: true)
                    .padding(.top, 40)
                    .contentTransition(.opacity)
                    .accessibilityLabel("Lettres : " + WordEngine.spoken(placed))
            } else {
                BoardLetters(text: consonants, size: consonants.count > 5 ? 64 : 88)
                    .padding(.top, 40)
                    .accessibilityLabel("Consonnes : " + WordEngine.spoken(consonants))
            }
            Rectangle().fill(Palette.tertiary).frame(width: 36, height: 1.5).padding(.top, 22)
            if session.usedHint {
                Text("« \(card.hint) »").font(Typo.serifItalic(20)).multilineTextAlignment(.center).lineSpacing(2)
                    .padding(.horizontal, 10).padding(.top, 22)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .tutorialTarget(.board)
        FlowLayout(spacing: 6) {
            ForEach(Array(session.wrongGuesses.enumerated()), id: \.offset) { _, guess in
                Text(WordEngine.normalize(guess)).scaledFont(12, .semibold).tracking(0.6)
                    .strikethrough().foregroundStyle(Palette.red)
                    .padding(.horizontal, 10).frame(minHeight: 26)
                    .background(Capsule().fill(Palette.redSoft))
                    .accessibilityLabel("Essai incorrect : \(guess)")
            }
        }.frame(minHeight: 26).padding(.top, 16)
        // The theme, near the consonants where the eyes are (the difficulty stays under the title).
        Text("Thème : " + card.category.rawValue).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1)
            .padding(.top, 6).tutorialTarget(.title)
        if mode == .daily && session.result == nil {
            Group {
                if session.checking {
                    Text("Vérification…").foregroundStyle(Palette.secondary)
                } else if let notice = session.notice {
                    Text(notice).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                } else if let left = session.guessesNotice {
                    Text(left).foregroundStyle(Palette.secondary)
                } else if session.usedVowels && !session.usedHint {
                    Text("Les voyelles du mot s’allument sur le clavier").foregroundStyle(Palette.accent)
                } else if catchUpDay != nil {
                    Text("Rattrapage : compte dans la semaine avec 5 min en plus.").foregroundStyle(Palette.tertiary)
                }
            }.scaledFont(12).padding(.top, 6)
        } else if session.result == nil && session.usedVowels && !session.usedHint {
            // Classique: the same line after the first hint.
            Text("Les voyelles du mot s’allument sur le clavier").foregroundStyle(Palette.accent).scaledFont(12).padding(.top, 6)
        }
        Spacer(minLength: 12)
        answerLine
        HStack(spacing: 8) {
            // After a minute without the hint, a small bubble on its left points at it (no room above,
            // under the answer); the buttons slide right to make room.
            if hintNudge && session.hintAvailable && session.result == nil && tutorial == nil {
                HintNudge().transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
            // One tap per hint: the word's vowels light up on the keyboard, then the sentence, then (Mot du
            // jour) the vowels take their places in the word one by one, the last one showing the word.
            Button {
                Haptics.selection()
                if session.nextRevealsWord { confirmReveal = true; return }
                withAnimation(reduceMotion ? nil : CNSNNTheme.ease) { session.revealHint(state: state) }
            } label: {
                HStack(spacing: 8) {
                    Text(hintTitle).fontWeight(.bold)
                    if !session.hintAvailable { Text("révélés") }
                    else if session.ranked && !session.nextRevealsWord { Text(HintCost.text(nextHintMs)) }
                }.scaledFont(13, .medium).foregroundStyle(Palette.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
            }.buttonStyle(PressStyle()).disabled(!session.hintAvailable || session.checking).opacity(session.hintAvailable ? 1 : 0.5)
            .accessibilityHint(session.hintsTaken == 0 ? "Allume les voyelles du mot sur le clavier." : !session.usedHint ? "Affiche une phrase sur le mot."
                               : session.nextRevealsWord ? "Affiche le mot et termine la partie." : session.hintAvailable ? "Place la voyelle suivante dans le mot." : "")
            .tutorialTarget(.hint)
            .animation(reduceMotion ? nil : CNSNNTheme.ease, value: hintNudge)
            // The Mot du jour has no Passer: the hints lead everyone to the word.
            if mode != .daily || tutorial != nil {
                Button { confirmSkip = true } label: {
                    Text("Passer").scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
                }.buttonStyle(PressStyle()).disabled(session.result != nil)
            }
        }.padding(.vertical, 12)
        LetterKeyboard(lit: session.vowels ?? "", press: press, delete: delete, moveCursor: { steps in edit { $0.move(by: steps) } }, submit: submit)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: session.vowels)
            .onChange(of: session.vowels) { _, lit in
                guard let lit, !lit.isEmpty else { return }
                Haptics.success()
                AccessibilityNotification.Announcement("Voyelles du mot : " + lit.map(String.init).joined(separator: ", ")).post()
            }
    }

    /// "Indice", "Indice 2", then "Lettre" for each vowel placed, "Afficher le mot" for the last.
    private var hintTitle: String {
        if !session.hintAvailable { return "Indices" }
        if session.nextRevealsWord { return "Afficher le mot" }
        return session.usedHint ? "Lettre" : session.hintsTaken == 0 ? "Indice" : "Indice 2"
    }
    private var nextHintMs: Int { session.usedHint ? HintCost.letterMs : session.hintsTaken == 0 ? HintCost.vowelsMs : HintCost.sentenceMs }
    /// The placed word with its vowels in gold, like the answer.
    static func goldVowels(_ text: String) -> AttributedString {
        var out = AttributedString()
        for character in text {
            var letter = AttributedString(String(character))
            letter.foregroundColor = Vowels.contains(character) ? Palette.accent : Palette.foreground
            out += letter
        }
        return out
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if session.answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            if !session.answer.isEmpty {
                AnswerLetters(answer: session.answer, cursor: session.result == nil ? session.cursor : nil, place: session.result == nil ? place : nil)
            }
            if session.result == nil, TypedAnswer(text: session.answer, cursor: session.cursor).inside == nil { Caret() }
        }
        .lineLimit(1).minimumScaleFactor(0.3)
        .frame(maxWidth: .infinity, minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.tertiary).frame(height: 1) }
        .padding(.horizontal, 24)
        .modifier(Shake(animatableData: shakes))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Votre réponse")
        .accessibilityValue(session.answer.isEmpty ? "vide" : session.answer)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().tint(Palette.secondary).controlSize(.large)
            Text("Lancement du chrono officiel…").scaledFont(15).foregroundStyle(Palette.secondary)
            Spacer()
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private func failedState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark").font(.system(size: 44, weight: .light)).foregroundStyle(Palette.secondary)
            Text("Mot du jour indisponible").scaledFont(22, .bold)
            Text(message + " Le mot reste caché tant que le chrono officiel n’a pas démarré.")
                .scaledFont(15).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button("Réessayer") { Haptics.selection(); session.retry(state: state) }.buttonStyle(PrimaryPillStyle(height: 54)).padding(.top, 8)
            Button("Retour") { dismiss() }.buttonStyle(GlassPillStyle())
            Spacer()
        }.padding(.horizontal, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.stack").font(.system(size: 44, weight: .light)).foregroundStyle(Palette.secondary)
            Text("Aucune carte").scaledFont(22, .bold)
            Text("Aucune carte disponible pour ces filtres. Revenez en arrière pour les modifier.")
                .scaledFont(15).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button("Retour") { dismiss() }.buttonStyle(GlassPillStyle()).padding(.top, 8)
            Spacer()
        }.padding(.horizontal, 24)
    }

    // MARK: Actions

    private func press(_ letter: String) {
        guard session.result == nil else { return }
        edit { $0.insert(letter) }
    }
    private func delete() { edit { $0.deleteBackward() } }
    private func place(_ index: Int) { edit { $0.place(index) } }
    private func edit(_ change: (inout TypedAnswer) -> Void) {
        var typed = TypedAnswer(text: session.answer, cursor: session.cursor)
        change(&typed)
        session.answer = typed.text; session.cursor = typed.cursor
    }
    private func submit() {
        guard session.result == nil, !session.checking else { return }
        guard WordEngine.normalize(session.answer).count >= 1 else { shake(); return }
        let before = session.wrongAnswers
        Task {
            await session.submit(mode: mode, state: state)
            if session.result != nil {
                finishedHere = true
            } else if session.wrongAnswers > before {
                shake()
                session.answer = ""
                if let feedback = session.feedback { AccessibilityNotification.Announcement(feedback).post() }
            } else if let notice = session.notice {
                AccessibilityNotification.Announcement(notice).post()
            }
        }
    }
    private func shake() {
        withAnimation(reduceMotion ? nil : .linear(duration: 0.42)) { shakes += 1 }
    }
    private func nextCard() {
        finishedHere = false
        session.load(mode: mode, category: category, difficulty: difficulty, state: state)
    }
}

// MARK: - Result sheet

private struct ResultSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var glow = false
    var result: Attempt
    var card: Card?
    var mode: GameMode
    var firstTry: Bool
    var usedHint: Bool
    var usedVowels = false
    /// Vowels placed in the word by the hints after the sentence.
    var letters = 0
    /// The last hint showed the word: ranked after every found word, on its time.
    var revealedWord = false
    var standing: DailyStanding?
    var pending: Bool
    var ranked: Bool
    var catchUp = false
    var next: () -> Void
    var close: () -> Void

    /// The hints' price ("+30 s", "+1 min") or "non".
    private var hintsTile: String {
        let ms = DailyScore.penaltyMs(usedHint: usedHint, usedVowels: usedVowels, letters: letters)
        return ms == 0 ? "non" : HintCost.text(ms)
    }
    private var hintsLabel: String { (usedHint && usedVowels) || letters > 0 ? "indices" : "indice" }

    var body: some View {
        VStack(spacing: 0) {
            Text(kicker).font(Typo.serifItalic(24)).foregroundStyle(result.correct ? Palette.mint : Palette.red)
            if let card {
                VowelReveal(word: card.wordFull.uppercased(), correct: result.correct, revealed: revealed)
                    .background {
                        // A brief golden glow once the last vowel is in place.
                        RadialGradient(colors: [Palette.accent.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 140)
                            .scaleEffect(x: 1.6, y: 0.8).opacity(glow ? 1 : 0).allowsHitTesting(false)
                    }
                    .padding(.top, 10)
                    .accessibilityElement(children: .ignore).accessibilityLabel(card.wordFull)
                Text("« \(card.hint) »").scaledFont(15).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).padding(.top, 6)
            }
            HStack(spacing: 10) {
                if catchUp {
                    // Counted in the week: the real time, the hints, then 5 minutes more.
                    tile(Format.clock(DailyScore.catchUpScoreMs(timeMs: result.timeMs, usedHint: usedHint, usedVowels: usedVowels, letters: letters, correct: result.correct)), "compté", Palette.foreground)
                    tile(hintsTile, hintsLabel, Palette.foreground)
                    tile("\(CatchUp.toPlay(state.catchUpDays()))", "à rattraper", Palette.foreground)
                } else if mode == .daily {
                    // The ranked time: the vowels add 30 s, the sentence 30 s more, a lost word counts ten.
                    if revealedWord {
                        // Shown by the last hint: classed after the found words, on its own time.
                        tile(Format.clock(result.timeMs), "mot révélé", Palette.foreground)
                    } else {
                        tile(Format.clock(DailyScore.scoreMs(timeMs: result.timeMs, usedHint: usedHint, usedVowels: usedVowels, letters: letters, correct: result.correct)), result.correct ? "temps" : "compté", Palette.foreground)
                    }
                    tile(hintsTile, hintsLabel, Palette.foreground)
                    tile("\(state.official?.currentStreak() ?? state.progress.streak())", "jours de série", Palette.foreground)
                } else {
                    tile(Format.clock(result.timeMs), "temps", Palette.foreground)
                    tile("\(state.progress.classicStreak)", "de suite", Palette.foreground)
                    tile(Format.number(state.progress.correctAnswers), "mots trouvés", Palette.foreground)
                }
            }.padding(.top, 18)
            if catchUp {
                if pending { officialLine.padding(.top, 12) }
            } else if mode == .daily && ranked {
                officialLine.padding(.top, 12)
            } else if !catchUp, result.correct, result.timeMs == state.progress.bestTimeMs {
                Label("Votre meilleur temps", systemImage: "trophy").scaledFont(13, .semibold).foregroundStyle(Palette.mint).padding(.top, 12)
            }
            if mode == .daily && !catchUp && state.uid != nil {
                ChallengePrompt(correct: result.correct) { state.challengeRequest += 1; close() }.padding(.top, 18)
            }
            HStack(spacing: 10) {
                if !catchUp {
                    ShareResultLink(attempt: result, card: card, mode: mode) {
                        Text("Partager")
                    }.buttonStyle(GlassPillStyle(height: 54))
                }
                Button(mode == .daily ? "Terminer" : "Mot suivant") {
                    Haptics.selection()
                    // Today's word: straight to the day's ranking.
                    if mode == .daily && ranked && !catchUp { state.leaderboardRequest += 1 }
                    if mode == .daily { close() } else { next() }
                }
                    .buttonStyle(PrimaryPillStyle(height: 54)).layoutPriority(1)
            }.padding(.top, 20)
            if catchUp {
                Text(pending ? "Votre partie est gardée sur cet iPhone et sera validée au retour du réseau."
                     : result.correct ? "Mot rattrapé : il compte au classement de la semaine avec 5 min en plus." : "Ce jour compte comme joué, sans mot trouvé.")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 14)
            } else if mode == .classic {
                Button("Retour à l’accueil", action: close).scaledFont(15, .medium).foregroundStyle(Palette.secondary).padding(.top, 14)
            } else {
                Text(pending ? "Votre partie est gardée sur cet iPhone et sera validée au retour du réseau." : "Votre défi du jour est enregistré. À demain !")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 14)
                // The form lives in Profil: this keeps it in sight once a day.
                Button("Une idée de mot ? Proposez-la") { Haptics.selection(); state.proposeRequest += 1; close() }
                    .scaledFont(13, .semibold).foregroundStyle(Palette.secondary).hitTarget().padding(.top, 6)
                    .accessibilityIdentifier("result.propose")
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 26)
        .background {
            let shape = RoundedRectangle(cornerRadius: 48, style: .continuous)
            shape.fill(.ultraThinMaterial).overlay(shape.fill(LinearGradient(colors: [Palette.sheetTop, Palette.sheetBottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Palette.glassHighlight, Palette.glassBorder], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: Palette.glassShadow, radius: 30, y: -20)
        }
        .onAppear { reveal(card?.wordFull.uppercased() ?? "") }
    }

    /// The signature moment: consonants stay, the vowels slide into the gaps one by one,
    /// each with a light tap, then the word glows. Missed words get grey vowels, no fanfare.
    private func reveal(_ word: String) {
        revealed = true
        let vowels = word.filter(Vowels.contains).count
        guard result.correct, !reduceMotion, vowels > 0 else { return }
        Task { @MainActor in
            for index in 0..<vowels {
                try? await Task.sleep(for: .seconds(index == 0 ? VowelReveal.firstDelay : VowelReveal.step))
                Haptics.key()
            }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.35)) { glow = true }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeIn(duration: 0.9)) { glow = false }
        }
    }

    /// Only real numbers: the percentile appears once the server has ranked the result.
    @ViewBuilder private var officialLine: some View {
        if pending {
            Label("Validation du temps officiel…", systemImage: "clock.arrow.circlepath").scaledFont(13, .semibold).foregroundStyle(Palette.secondary)
        } else if let standing, result.correct, let rank = standing.rank {
            VStack(spacing: 2) {
                if rank == 1 {
                    Label("Vous êtes le numéro 1 !", systemImage: "trophy.fill").scaledFont(17, .bold).foregroundStyle(Palette.mint)
                } else if let top = standing.topPercent {
                    Text("Top \(top) %").scaledFont(17, .bold).foregroundStyle(Palette.mint)
                }
                Text(Format.ordinal(rank) + " sur \(standing.players) aujourd’hui").scaledFont(13).foregroundStyle(Palette.secondary)
            }.accessibilityElement(children: .combine)
        } else if let standing, !result.correct, standing.tried > 1 {
            Text("\(standing.tried) joueurs ont tenté ce mot aujourd’hui").scaledFont(13).foregroundStyle(Palette.secondary)
        }
    }

    private var kicker: String {
        if revealedWord { return mode == .daily ? "Voici le mot du jour." : "Voici le mot." }
        guard result.correct else { return "Pas cette fois…" }
        return firstTry ? "Du premier coup, sans indice." : "Trouvé en \(Format.clock(result.timeMs))."
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).scaledFont(22, .bold).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Keyboard

/// AZERTY glass keyboard laid out like the iPhone's French one: same rows and key sizes, ⌫ at the right
/// end of the third row, a wide space bar with Valider where Return goes, no dead zone between keys (a
/// touch in a gap goes to the nearest key) and the letter popping up above the finger. Every key is
/// grey: only the first hint lights the word's vowels in gold.
struct LetterKeyboard: View {
    /// The letters lit in gold (the word's vowels, once the first hint is taken).
    var lit: String = ""
    var press: (String) -> Void
    var delete: () -> Void
    /// A long press on ⌫ erases the whole answer, when the screen offers it.
    var clear: (() -> Void)? = nil
    /// A slide on the space bar moves the caret, one letter every few points, as on the iPhone.
    var moveCursor: ((Int) -> Void)? = nil
    var submit: () -> Void
    /// Valider, in key widths: narrow enough that a thumb aiming at the space bar does not send the answer.
    static let submitUnits: CGFloat = 2.2
    private let rows = ["AZERTYUIOP", "QSDFGHJKLM", "WXCVBN"]
    /// One key with its share of the gaps: the touch area. The cap is drawn inside it.
    static let rowHeight: CGFloat = 57.5
    /// An iPad with a keyboard attached (or a Mac): typing on it works like the keys on screen.
    @FocusState private var hardwareKeys: Bool
    var body: some View {
        keys
            .focusable(interactions: .edit)
            .focused($hardwareKeys)
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat]) { key in handle(key) }
            .onAppear { hardwareKeys = true }
    }

    /// Letters (accents dropped), space, ⌫, ⏎ and ← → from a hardware keyboard.
    private func handle(_ key: KeyPress) -> KeyPress.Result {
        if key.modifiers.contains(.command) || key.modifiers.contains(.control) { return .ignored }
        switch key.key {
        case .delete: delete(); return .handled
        case .return: if key.phase == .down { submit() }; return .handled
        case .leftArrow: if let moveCursor { moveCursor(-1); return .handled }; return .ignored
        case .rightArrow: if let moveCursor { moveCursor(1); return .handled }; return .ignored
        case .space: if key.phase == .down { press(" ") }; return .handled
        default: break
        }
        guard key.phase == .down else { return .ignored }
        let letter = key.characters.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).uppercased()
        guard letter.unicodeScalars.count == 1, let scalar = letter.unicodeScalars.first, (65...90).contains(scalar.value) else { return .ignored }
        press(letter)
        return .handled
    }

    private var keys: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 10
            VStack(spacing: 0) {
                letterRow(rows[0], unit)
                letterRow(rows[1], unit)
                HStack(spacing: 0) {
                    // Where the iPhone has ⇧: left empty, so W to N sit where the thumb expects them, and
                    // the slot of its ´ key stays empty before ⌫.
                    Color.clear.frame(width: unit * 1.6)
                    letterRow(rows[2], unit)
                    Spacer(minLength: 0)
                    KeyCap(label: "⌫", width: unit * 1.35, action: delete, longPress: clear)
                        .accessibilityLabel("Effacer")
                }
                HStack(spacing: 0) {
                    // Space for answers in several words (Les Aristochats); spaces are ignored when checking.
                    KeyCap(label: "espace", width: geo.size.width - unit * Self.submitUnits, action: { press(" ") }, slide: moveCursor)
                        .accessibilityLabel("Espace")
                    Button("Valider") { Haptics.selection(); submit() }
                        .buttonStyle(PrimaryPillStyle(height: Self.rowHeight - 10))
                        .padding(.horizontal, 3)
                        .frame(width: unit * Self.submitUnits, height: Self.rowHeight)
                }
            }
        }
        .frame(height: Self.rowHeight * 4)
        .padding(.horizontal, 3).padding(.vertical, 6)
        .glassCard(radius: 30, padding: 0)
        // Edge to edge like the iPhone's: A and P reach the sides of the screen (the game has 16 points of margin).
        .padding(.horizontal, -14)
        // The iPhone keeps a strip under its keys (globe, dictation): the keys sit as high as there.
        .padding(.bottom, 25)
    }

    private func letterRow(_ row: String, _ unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row), id: \.self) { letter in
                KeyCap(label: String(letter), vowel: lit.contains(letter), width: unit) { press(String(letter)) }
            }
        }
    }
}

/// One key: the whole cell takes the touch, the cap sits inside it with the iPhone's gaps around.
private struct KeyCap: View {
    var label: String
    var vowel = false
    var width: CGFloat
    var action: () -> Void
    var longPress: (() -> Void)? = nil
    /// Called with the letters to move by while the finger slides along the key (space bar).
    var slide: ((Int) -> Void)? = nil
    @State private var slid = 0
    var body: some View {
        Button { Haptics.key(); action() } label: {
            Group {
                if label == "⌫" { Image(systemName: "delete.left").font(.system(size: 20, weight: .regular)) }
                else { Text(label).font(.system(size: label.count > 1 ? 16 : 25, weight: .regular)) }
            }
            .foregroundStyle(vowel ? Palette.onAccent : Palette.foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(KeyStyle(vowel: vowel, popup: label.count == 1 && label != "⌫" ? label : nil))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            guard let longPress else { return }
            Haptics.retry(); longPress()
        }, including: longPress == nil ? .subviews : .all)
        .highPriorityGesture(DragGesture(minimumDistance: 10).onChanged { drag in
            guard let slide else { return }
            let steps = Int(drag.translation.width / 12)
            if steps != slid { Haptics.selection(); slide(steps - slid); slid = steps }
        }.onEnded { _ in slid = 0 }, including: slide == nil ? .subviews : .all)
        .frame(width: max(width, 0), height: LetterKeyboard.rowHeight)
    }
}

/// The cap, with the iPhone's popup: the letter shows larger above the finger while it is down.
private struct KeyStyle: ButtonStyle {
    var vowel: Bool
    /// The letter shown above the finger; nil for ⌫ and the space bar, which darken instead.
    var popup: String?
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .background {
                if vowel { shape.fill(LinearGradient(colors: [Palette.accentTop, Palette.accentBottom], startPoint: .top, endPoint: .bottom)) }
                else { shape.fill(pressed && popup == nil ? Palette.fill2 : Palette.fill1).overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 1)) }
            }
            .padding(.horizontal, 3).padding(.vertical, 6.25)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if let popup, pressed {
                    Text(popup).font(.system(size: 34, weight: .regular))
                        .foregroundStyle(vowel ? Palette.onAccent : Palette.foreground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if vowel { shape.fill(LinearGradient(colors: [Palette.accentTop, Palette.accentBottom], startPoint: .top, endPoint: .bottom)) }
                            else { shape.fill(Palette.surface).overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 1)) }
                        }
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .padding(.horizontal, -2)
                        .frame(height: 56)
                        .offset(y: -50)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The typed answer as one text, vowels in gold: when a long answer has to shrink, every letter
/// shrinks by the same amount (separate texts each shrank on their own, wide letters like M more).
struct AnswerLetters: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let answer: String
    /// A wrong answer kept on screen: all in red until the next key.
    var wrong = false
    /// Cursor inside the word, drawn in the same text so the whole line still shrinks evenly (at the end, the
    /// screen draws its own `Caret`).
    var cursor: Int? = nil
    /// A touch or a slide on the word puts the caret before the letter under the finger.
    var place: ((Int) -> Void)? = nil
    var body: some View {
        Group {
            if let inside = TypedAnswer(text: answer, cursor: cursor).inside {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    letters(caret: inside, visible: reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0)
                }
            } else {
                letters(caret: nil, visible: false)
            }
        }
        .overlay {
            if let place {
                GeometryReader { geo in
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                            guard geo.size.width > 0 else { return }
                            place(Int((drag.location.x / geo.size.width * CGFloat(answer.count)).rounded()))
                        })
                }
                .padding(.vertical, -12)
            }
        }
    }

    private func letters(caret: Int?, visible: Bool) -> some View {
        var line = AttributedString()
        for (index, character) in answer.enumerated() {
            if index == caret {
                var bar = AttributedString("|")
                bar.foregroundColor = visible ? Palette.foreground : .clear
                line += bar
            }
            var letter = AttributedString(String(character))
            letter.foregroundColor = wrong ? Palette.red : Vowels.contains(character) ? Palette.accent : Palette.foreground
            line += letter
        }
        // The letter spacing does not shrink with the letters: a long expression gets a tighter one, so it
        // shrinks less and stays whole on the line (« QUESTCEQUONAFAITAUBONDIEU »).
        return Text(line).tracking(answer.count > 14 ? 1.5 : 4.4).scaledFont(30, .medium)
    }
}

struct Caret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 2).fill(Palette.foreground).frame(width: 2.5, height: 30).opacity(visible ? 1 : 0).padding(.leading, 2)
        }
    }
}

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4) * (1 - animatableData.truncatingRemainder(dividingBy: 1)), y: 0))
    }
}

/// Wraps children onto several lines, centred or from the leading edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var centred = true
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = centred ? bounds.midX - row.width / 2 : bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current); current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// The word with its vowels sliding into the gaps between the consonants.
/// The board's letters: the consonants, or the word with its vowels placed (in gold). An expression goes on
/// two or three lines, cut between its words (WordEngine.lines), and the letters shrink only when a line still
/// does not fit the screen: the whole board always shows, never cut (« Qu’est-ce qu’on a fait au Bon Dieu »).
struct BoardLetters: View {
    let text: String
    /// The size of a short board on one line; an expression on several lines is a little smaller.
    var size: CGFloat
    var tracking: CGFloat = 3
    var gold = false
    var body: some View {
        let lines = WordEngine.lines(text)
        let shown = lines.joined(separator: "\n")
        Group {
            if gold { Text(GameView.goldVowels(shown)) } else { Text(shown) }
        }
        .font(Typo.serif(lines.count > 1 ? min(size, 50) : size)).tracking(tracking)
        .multilineTextAlignment(.center)
        .lineLimit(lines.count).minimumScaleFactor(0.3)
    }
}

struct VowelReveal: View {
    static let firstDelay = 0.35
    static let step = 0.16
    var word: String
    var correct: Bool
    var revealed: Bool
    /// Largest letter size, and the width the whole word must fit in.
    var maxSize: CGFloat = 42
    var width: CGFloat = 318
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Letters are separate views here (the vowels slide in), so the size is chosen for the
    /// whole word from its length, instead of each letter shrinking on its own. It does not
    /// change while the vowels slide in. A long expression goes on two or three lines, cut
    /// between its words, so it stays big enough to read (« QU’EST-CE QU’ON A / FAIT AU BON DIEU »).
    var body: some View {
        let lines = word.count > 16 ? WordEngine.lines(word, maxChars: 16) : [word]
        let longest = lines.map(\.count).max() ?? 1
        let size = min(maxSize, width / (CGFloat(max(longest, 1)) * 0.8))
        VStack(spacing: size * 0.12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { number, line in
                // The vowels still slide in one after the other across the lines.
                letters(line, firstVowel: lines[..<number].reduce(0) { total, earlier in total + earlier.filter(Vowels.contains).count })
            }
        }
        .font(.system(size: size, weight: .heavy)).tracking(size * 0.06).fixedSize()
    }
    private func letters(_ line: String, firstVowel: Int) -> some View {
        let letters = Array(line.enumerated())
        return HStack(spacing: 0) {
            ForEach(letters, id: \.offset) { index, character in
                if Vowels.contains(character) {
                    let order = firstVowel + letters[..<index].filter { Vowels.contains($0.element) }.count
                    CollapseLayout(progress: revealed ? 1 : 0) {
                        Text(String(character))
                            .foregroundStyle(correct ? Palette.accent : Palette.secondary)
                            .shadow(color: correct ? Palette.accent.opacity(0.6) : .clear, radius: 12)
                    }
                    .opacity(revealed ? 1 : 0)
                    .animation(animation(order), value: revealed)
                } else {
                    Text(String(character)).foregroundStyle(Palette.foreground)
                }
            }
        }
    }
    private func animation(_ order: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        let delay = Self.firstDelay + Double(order) * Self.step
        return correct ? .spring(response: 0.42, dampingFraction: 0.62).delay(delay) : .easeOut(duration: 0.5).delay(delay)
    }
}

/// "Un indice ?": a light bubble whose arrow points right at the Indice button. It blinks for its
/// first 5 seconds, then stays.
/// What each hint adds to the Mot du jour time (DailyScore): the vowels, the sentence, then each placed vowel.
enum HintCost {
    static let vowelsMs = DailyScore.vowelsPenaltyMs
    static let sentenceMs = DailyScore.hintPenaltyMs - DailyScore.vowelsPenaltyMs
    static let letterMs = DailyScore.letterPenaltyMs
    /// " · voyelles +30 s", " · indices +1 min 30 s" in the day's ranking, nothing without a hint.
    static func detail(usedHint: Bool, usedVowels: Bool, letters: Int = 0) -> String {
        let ms = DailyScore.penaltyMs(usedHint: usedHint, usedVowels: usedVowels, letters: letters)
        guard ms > 0 else { return "" }
        return (letters > 0 || (usedHint && usedVowels) ? " · indices " : usedHint ? " · indice " : " · voyelles ") + text(ms)
    }
    /// "+30 s", "+1 min", "+1 min 30 s".
    static func text(_ ms: Int) -> String {
        let minutes = ms / 60_000, seconds = ms % 60_000 / 1000
        return minutes == 0 ? "+\(seconds) s" : seconds == 0 ? "+\(minutes) min" : "+\(minutes) min \(seconds) s"
    }
}

private struct HintNudge: View {
    /// Before the first hint (from the start), and before the second (from the first).
    static let delayMs = 30_000
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        HStack(spacing: 0) {
            Text("Un indice ?").scaledFont(13, .semibold).foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Palette.foreground))
            Triangle(up: false).fill(Palette.foreground).frame(width: 12, height: 6)
                .rotationEffect(.degrees(-90)).frame(width: 6, height: 12)
        }
        .fixedSize()
        .opacity(dim ? 0.25 : 1)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .allowsHitTesting(false)
        .accessibilityLabel("Un indice ? Le bouton Indice est juste à droite.")
        .task {
            guard !reduceMotion else { return }
            for _ in 0..<5 {
                withAnimation(.easeInOut(duration: 0.5)) { dim = true }
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeInOut(duration: 0.5)) { dim = false }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

// MARK: - Celebration

/// A found word (Classique and Mot du jour): the word in big, a breath, then its letters burst and fall
/// as confetti (vowels gold, consonants ivory, a few turquoise). On the ranked Mot du jour, the place
/// follows in big ("Vous êtes 12e"), then the result sheet comes up. A tap skips to the sheet. Same
/// timings and colours as Android's WordCelebration.
struct WordCelebration: View {
    let word: String
    /// The Mot du jour place, read live (the server ranks the result a moment after the finish).
    var showsRank: Bool
    var standing: () -> DailyStanding?
    /// The sheet may come up now; `ended` removes this overlay once the confetti have fallen.
    var showSheet: () -> Void
    var ended: () -> Void
    @State private var start = Date()
    @State private var burst: [LetterBurst.Particle] = []
    @State private var place: (shown: Int, rank: Int, players: Int)?
    @State private var pop = false
    @State private var sheetUp = false

    var body: some View {
        GeometryReader { geo in
            let letters = Array(word)
            let layout = LetterBurst.layout(count: letters.count, width: geo.size.width, centerY: geo.size.height * 0.36)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    LetterBurst.draw(in: &context, size: size, t: t, letters: letters, layout: layout, particles: burst)
                } symbols: {
                    LetterBurst.symbols(letters: letters, size: layout.size)
                }
            }
            .onAppear {
                burst = LetterBurst.particles(letters: letters, layout: layout)
            }
            if let place {
                RankReveal(shown: place.shown, rank: place.rank, players: place.players, pop: pop)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.36)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .allowsHitTesting(!sheetUp)
        .onTapGesture { up(); ended() }
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func up() { guard !sheetUp else { return }; sheetUp = true; withAnimation(.easeOut(duration: 0.25)) { place = nil }; showSheet() }

    @MainActor private func run() async {
        try? await Task.sleep(for: .seconds(LetterBurst.explodeAt))
        Haptics.burst()
        guard showsRank else {
            try? await Task.sleep(for: .seconds(0.25)); up()
            try? await Task.sleep(for: .seconds(LetterBurst.duration - LetterBurst.explodeAt - 0.25)); ended()
            return
        }
        // Waits for the place (up to 3 s), then counts from the number of players down to it.
        var waited = 0.0
        while standing()?.rank == nil, waited < 3 { try? await Task.sleep(for: .seconds(0.1)); waited += 0.1 }
        guard !sheetUp, let found = standing(), let rank = found.rank else { up(); try? await Task.sleep(for: .seconds(1.5)); ended(); return }
        if waited < 0.4 { try? await Task.sleep(for: .seconds(0.4 - waited)) }
        let players = max(found.players, rank)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { place = (players, rank, players) }
        for value in RankReveal.steps(from: players, to: rank) {
            try? await Task.sleep(for: .seconds(value - rank < 4 ? 0.12 : 0.045))
            guard !sheetUp else { return }
            place = (value, rank, players)
            Haptics.key()
        }
        Haptics.success()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { pop = true }
        try? await Task.sleep(for: .seconds(0.25))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
        try? await Task.sleep(for: .seconds(1.4))
        up()
        try? await Task.sleep(for: .seconds(0.5)); ended()
    }
}

/// "Vous êtes" / "12e" in big gold / "sur 87 joueurs aujourd'hui".
private struct RankReveal: View {
    var shown: Int
    var rank: Int
    var players: Int
    var pop: Bool
    /// From the number of players down to the place, in shrinking jumps (about 12 steps).
    static func steps(from players: Int, to rank: Int) -> [Int] {
        var values: [Int] = [], value = players
        while value > rank { value = max(rank, value - max(1, Int((Double(value - rank) / 5).rounded()))); values.append(value) }
        return values
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("Vous êtes").font(Typo.serifItalic(30)).foregroundStyle(Palette.foreground.opacity(0.85))
            HStack(alignment: .top, spacing: 2) {
                Text("\(shown)").font(.system(size: 120, weight: .heavy)).monospacedDigit().contentTransition(.numericText(countsDown: true))
                Text(shown == 1 ? "er" : "e").font(.system(size: 44, weight: .heavy)).padding(.top, 16)
            }
            .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.77), Palette.accent], startPoint: .top, endPoint: .bottom))
            .shadow(color: Palette.accent.opacity(0.45), radius: 24)
            .scaleEffect(pop ? 1.12 : 1)
            .lineLimit(1).minimumScaleFactor(0.5)
            Text("sur \(Format.number(players)) joueur\(players > 1 ? "s" : "") aujourd’hui").font(.system(size: 16)).foregroundStyle(Palette.secondary)
        }
        .fixedSize()
    }
}

/// The letters of the found word and their confetti, drawn in one Canvas. Positions are a function of
/// time (linear drag and gravity), so nothing is stored per frame.
enum LetterBurst {
    static let explodeAt = 0.55
    static let duration = 3.0
    struct Layout { let xs: [CGFloat]; let y: CGFloat; let size: CGFloat }
    struct Particle {
        let symbol: String
        let x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        /// Drag and gravity: the word's letters fall fast, the small ones float down.
        let drag: CGFloat, gravity: CGFloat
        let spin: CGFloat, turn: CGFloat, phase: CGFloat, scale: CGFloat
        let big: Bool
    }
    static let colors: [Color] = [Palette.accent, Palette.foreground, Palette.mint]

    static func layout(count: Int, width: CGFloat, centerY: CGFloat) -> Layout {
        let size = min(60, width * 0.86 / (CGFloat(max(count, 1)) * 0.68))
        let step = size * 0.68
        let xs = (0..<count).map { width / 2 + (CGFloat($0) - CGFloat(count - 1) / 2) * step }
        return Layout(xs: xs, y: centerY, size: size)
    }

    /// Only what is drawn: the gaps of an expression ("Qu’est-ce qu’on a fait au Bon Dieu") are no
    /// symbol (an empty symbol made SwiftUI's Canvas stop the app), and each tag is listed once, flat.
    struct Symbol: Identifiable { let id: String; let text: String; let size: CGFloat?; let color: Color }

    static func symbolTags(letters: [Character]) -> [Symbol] {
        var tags: [Symbol] = []
        for (index, letter) in letters.enumerated() where drawable(letter) {
            tags.append(Symbol(id: "w\(index)", text: String(letter), size: nil, color: Vowels.contains(letter) ? Palette.accent : Palette.foreground))
        }
        for letter in Array(Set(letters.filter(drawable).map { String($0) })).sorted() {
            for color in colors.indices { tags.append(Symbol(id: "s\(letter)\(color)", text: letter, size: 22, color: colors[color])) }
        }
        return tags
    }

    static func drawable(_ letter: Character) -> Bool { !letter.isWhitespace }

    @ViewBuilder static func symbols(letters: [Character], size: CGFloat) -> some View {
        ForEach(symbolTags(letters: letters)) { symbol in
            Text(symbol.text).font(.system(size: max(symbol.size ?? size, 1), weight: .heavy))
                .foregroundStyle(symbol.color).tag(symbol.id)
        }
    }

    static func particles(letters: [Character], layout: Layout) -> [Particle] {
        let perLetter = max(4, min(11, 100 / max(letters.count, 1)))
        var all: [Particle] = []
        let shown = letters.filter(drawable)
        for (index, letter) in letters.enumerated() where drawable(letter) {
            let x = layout.xs[index], dx = x - layout.xs[letters.count / 2]
            all.append(Particle(symbol: "w\(index)", x: x, y: layout.y, vx: dx * 2.4 + .random(in: -80...80), vy: .random(in: -520 ... -260),
                                drag: 0.5, gravity: 1100, spin: 0, turn: .random(in: -5...5), phase: 0, scale: 1, big: true))
            for _ in 0..<perLetter {
                let angle = CGFloat.random(in: 0 ..< 2 * .pi), speed = CGFloat.random(in: 160...580)
                let pick = shown.randomElement() ?? letter, roll = Double.random(in: 0..<1)
                let color = roll < 0.15 ? 2 : (Vowels.contains(pick) ? 0 : 1)
                all.append(Particle(symbol: "s\(pick)\(color)", x: x + .random(in: -10...10), y: layout.y + .random(in: -20...20),
                                    vx: cos(angle) * speed, vy: sin(angle) * speed - 220, drag: 2.6, gravity: 620,
                                    spin: .random(in: 0..<6), turn: .random(in: -6...6), phase: .random(in: 0..<6), scale: .random(in: 0.6...1.3), big: false))
            }
        }
        return all
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double, letters: [Character], layout: Layout, particles: [Particle]) {
        if t < explodeAt {
            // The word, gathering itself before it bursts.
            let tension = max(0, (t - 0.25) / (explodeAt - 0.25))
            let scale = 1 + 0.08 * tension, shake = 2 * tension
            var glow = context
            glow.opacity = 0.35 * tension
            glow.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 170, y: layout.y - 90, width: 340, height: 180)),
                      with: .radialGradient(Gradient(colors: [Palette.accent, .clear]), center: CGPoint(x: size.width / 2, y: layout.y), startRadius: 0, endRadius: 170))
            for index in letters.indices {
                guard let symbol = context.resolveSymbol(id: "w\(index)") else { continue }
                let x = size.width / 2 + (layout.xs[index] - size.width / 2) * scale + .random(in: -shake...shake)
                var letter = context
                letter.translateBy(x: x, y: layout.y + .random(in: -shake...shake))
                letter.scaleBy(x: scale, y: scale)
                letter.draw(symbol, at: .zero)
            }
            return
        }
        let s = t - explodeAt
        // A short flash where the word was.
        if s < 0.25 {
            var flash = context
            flash.opacity = 0.7 * (1 - s / 0.25)
            flash.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.77), Palette.accent.opacity(0.5), .clear]),
                       center: CGPoint(x: size.width / 2, y: layout.y), startRadius: 0, endRadius: 260))
        }
        let fade = max(0, min(1, (duration - t) / 0.6))
        for particle in particles {
            guard let symbol = context.resolveSymbol(id: particle.symbol) else { continue }
            let k = particle.drag, e = exp(-k * s), travel = (1 - e) / k
            let x = particle.x + particle.vx * travel + (particle.big ? 0 : sin(s * 4 + particle.phase) * 8)
            let y = particle.y + particle.vy * travel + particle.gravity / k * (s - travel)
            guard y < size.height + 60 else { continue }
            var piece = context
            piece.opacity = fade
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(particle.spin + particle.turn * s))
            piece.scaleBy(x: particle.scale * (particle.big ? 1 : cos(s * 4 + particle.phase)), y: particle.scale)
            piece.draw(symbol, at: .zero)
        }
    }
}
