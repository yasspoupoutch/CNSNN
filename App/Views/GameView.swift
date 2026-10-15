import SwiftUI
import CNSNNCore

struct GameView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = GameSession()
    @State private var confirmSkip = false
    @State private var reporting = false
    @State private var reportReason = ""
    @State private var shakes: CGFloat = 0
    @State private var finishedHere = false
    let mode: GameMode
    var category: CNSNNCore.Category? = nil
    var difficulty: Difficulty? = nil

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
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
            if let result = session.result {
                Palette.dim.ignoresSafeArea().transition(.opacity)
                VStack {
                    Spacer()
                    ResultSheet(result: result, card: session.card, mode: mode, firstTry: finishedHere && session.wrongAnswers == 0 && !session.usedHint,
                                usedHint: session.usedHint, standing: session.standing, pending: session.pendingOfficial, ranked: session.ranked,
                                next: nextCard, close: { dismiss() })
                        .padding(.horizontal, 8)
                }.transition(.move(edge: .bottom))
            }
        }
        .animation(reduceMotion ? nil : CNSNNTheme.ease, value: session.result?.id)
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
        .task { if session.card == nil && session.result == nil { session.load(mode: mode, category: category, difficulty: difficulty, state: state) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.resume() } else { session.pause() } }
        .confirmationDialog("Révéler le mot et terminer cette carte ?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Révéler le mot", role: .destructive) { finishedHere = true; session.finish(correct: false, mode: mode, state: state) }
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
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text(mode == .daily ? "Mot du jour" : "Classique").scaledFont(16, .semibold)
                if let card = session.card {
                    Text("\(card.category.rawValue) · \(card.difficulty.rawValue)").scaledFont(12).foregroundStyle(Palette.tertiary)
                }
            }.lineLimit(1).accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        }
        .frame(minHeight: 48)
    }

    // MARK: Board

    @ViewBuilder private func board(_ card: Card) -> some View {
        let consonants = card.wordNoVowels
        Text(consonants)
            .font(Typo.serif(consonants.count > 5 ? 64 : 88)).tracking(3)
            .lineLimit(1).minimumScaleFactor(0.35)
            .padding(.top, 40)
            .accessibilityLabel("Consonnes : " + consonants.map(String.init).joined(separator: ", "))
        Rectangle().fill(Palette.tertiary).frame(width: 36, height: 1.5).padding(.top, 22)
        if session.usedHint {
            Text("« \(card.hint) »").font(Typo.serifItalic(25)).multilineTextAlignment(.center).lineSpacing(2)
                .padding(.horizontal, 10).padding(.top, 22)
                .transition(.opacity.combined(with: .offset(y: 8)))
        }
        FlowLayout(spacing: 6) {
            ForEach(Array(session.wrongGuesses.enumerated()), id: \.offset) { _, guess in
                Text(WordEngine.normalize(guess)).scaledFont(12, .semibold).tracking(0.6)
                    .strikethrough().foregroundStyle(Palette.red)
                    .padding(.horizontal, 10).frame(minHeight: 26)
                    .background(Capsule().fill(Palette.redSoft))
                    .accessibilityLabel("Essai incorrect : \(guess)")
            }
        }.frame(minHeight: 26).padding(.top, 16)
        if mode == .daily && session.result == nil {
            Group {
                if session.checking {
                    Text("Vérification…").foregroundStyle(Palette.secondary)
                } else if let notice = session.notice {
                    Text(notice).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
                } else if let left = session.guessesNotice {
                    Text(left).foregroundStyle(Palette.secondary)
                } else {
                    Text(session.secret ? "Chrono officiel. 20 essais pour trouver le mot." : session.ranked ? "Chrono officiel. Les erreurs ne terminent pas la partie." : "Les erreurs ne terminent pas la partie.")
                        .foregroundStyle(Palette.tertiary)
                }
            }.scaledFont(12).padding(.top, 6)
        }
        Spacer(minLength: 12)
        answerLine
        HStack(spacing: 8) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? nil : CNSNNTheme.ease) { session.revealHint(state: state) }
            } label: {
                HStack(spacing: 8) {
                    Text("Indice").fontWeight(.bold)
                    Text(session.usedHint ? "révélé" : "points ÷ 2")
                }.scaledFont(13, .medium).foregroundStyle(Palette.foreground)
                    .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
            }.buttonStyle(PressStyle()).disabled(session.usedHint || session.result != nil || session.checking).opacity(session.usedHint ? 0.5 : 1)
            Button { confirmSkip = true } label: {
                Text("Passer").scaledFont(13, .medium).foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 16).frame(minHeight: 36).glassCapsule().hitTarget()
            }.buttonStyle(PressStyle()).disabled(session.result != nil)
        }.padding(.vertical, 12)
        LetterKeyboard(press: press, delete: delete, submit: submit)
    }

    private var answerLine: some View {
        HStack(spacing: 2) {
            if session.answer.isEmpty {
                Text("votre réponse").font(Typo.serifItalic(22)).foregroundStyle(Palette.tertiary)
            }
            ForEach(Array(session.answer.enumerated()), id: \.offset) { _, character in
                Text(String(character)).scaledFont(30, .medium).tracking(2.4)
                    .foregroundStyle(Vowels.contains(character) ? Palette.accent : Palette.foreground)
            }
            if session.result == nil { Caret() }
        }
        .lineLimit(1).minimumScaleFactor(0.4)
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
        guard session.result == nil, session.answer.count < 40 else { return }
        // No leading or double spaces.
        if letter == " ", session.answer.isEmpty || session.answer.hasSuffix(" ") { return }
        session.answer += letter
    }
    private func delete() {
        guard !session.answer.isEmpty else { return }
        session.answer.removeLast()
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
    var standing: DailyStanding?
    var pending: Bool
    var ranked: Bool
    var next: () -> Void
    var close: () -> Void

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
                tile("+\(result.points)", "points", Palette.foreground)
                tile(Format.clock(result.timeMs), "temps", Palette.foreground)
                if mode == .daily { tile("\(state.official?.currentStreak() ?? state.progress.streak())", "jours de série", Palette.foreground) }
                else { tile(Format.number(state.progress.score), "total", Palette.foreground) }
            }.padding(.top, 18)
            if mode == .daily && ranked {
                officialLine.padding(.top, 12)
            } else if result.correct, result.timeMs == state.progress.bestTimeMs {
                Label("Votre meilleur temps", systemImage: "trophy").scaledFont(13, .semibold).foregroundStyle(Palette.mint).padding(.top, 12)
            }
            if mode == .daily && state.uid != nil {
                ChallengePrompt(correct: result.correct) { state.challengeRequest += 1; close() }.padding(.top, 18)
            }
            HStack(spacing: 10) {
                ShareResultLink(attempt: result, card: card, mode: mode) {
                    Text("Partager")
                }.buttonStyle(GlassPillStyle(height: 54))
                Button(mode == .daily ? "Terminer" : "Mot suivant") {
                    Haptics.selection()
                    if mode == .daily { close() } else { next() }
                }
                    .buttonStyle(PrimaryPillStyle(height: 54)).layoutPriority(1)
            }.padding(.top, 20)
            if mode == .classic {
                Button("Retour à l’accueil", action: close).scaledFont(15, .medium).foregroundStyle(Palette.secondary).padding(.top, 14)
            } else {
                Text(pending ? "Votre partie est gardée sur cet iPhone et sera validée au retour du réseau." : "Votre défi du jour est enregistré. À demain !")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 14)
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
        } else if let standing, !result.correct, standing.players > 1 {
            Text("\(standing.players) joueurs ont tenté ce mot aujourd’hui").scaledFont(13).foregroundStyle(Palette.secondary)
        }
    }

    private var kicker: String {
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

/// AZERTY glass keyboard from the prototype; vowels are highlighted in gold.
struct LetterKeyboard: View {
    var press: (String) -> Void
    var delete: () -> Void
    var submit: () -> Void
    private let rows = ["AZERTYUIOP", "QSDFGHJKLM", "WXCVBN"]
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let key = (geo.size.width - 9 * 4) / 10
                VStack(spacing: 8) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(Array(row), id: \.self) { letter in
                                KeyCap(label: String(letter), vowel: Vowels.contains(letter), width: key) { press(String(letter)) }
                            }
                            if row == rows.last {
                                KeyCap(label: "⌫", vowel: false, width: key * 2 + 4, action: delete)
                                    .accessibilityLabel("Effacer")
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 44 * 3 + 16)
            // Space for answers in several words (Les Aristochats); spaces are ignored when checking.
            HStack(spacing: 6) {
                KeyCap(label: "espace", vowel: false, width: 110) { press(" ") }
                    .accessibilityLabel("Espace")
                Button("Valider") { Haptics.selection(); submit() }
                    .buttonStyle(PrimaryPillStyle(height: 48))
            }.padding(.horizontal, 4).padding(.top, 2)
        }
        .padding(.horizontal, 6).padding(.vertical, 10)
        .glassCard(radius: 30, padding: 0)
    }
}

private struct KeyCap: View {
    var label: String
    var vowel: Bool
    var width: CGFloat
    var action: () -> Void
    var body: some View {
        Button { Haptics.key(); action() } label: {
            Text(label).font(.system(size: 19, weight: .medium))
                .foregroundStyle(vowel ? Palette.onAccent : Palette.foreground)
                .frame(width: max(width, 0), height: 44)
                .background {
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    if vowel { shape.fill(LinearGradient(colors: [Palette.accentTop, Palette.accentBottom], startPoint: .top, endPoint: .bottom)) }
                    else { shape.fill(Palette.fill1).overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 1)) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(PressStyle(scale: 0.88))
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

/// Wraps children onto several centred lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
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
    /// change while the vowels slide in.
    var body: some View {
        let size = min(maxSize, width / (CGFloat(max(word.count, 1)) * 0.8))
        letters.font(.system(size: size, weight: .heavy)).tracking(size * 0.06).fixedSize()
    }
    private var letters: some View {
        let letters = Array(word.enumerated())
        return HStack(spacing: 0) {
            ForEach(letters, id: \.offset) { index, character in
                if Vowels.contains(character) {
                    let order = letters[..<index].filter { Vowels.contains($0.element) }.count
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
