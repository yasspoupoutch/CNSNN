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
            AmbientBackground()
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
                if state.cloud != nil, let card = session.card, !card.id.hasPrefix("seed-"), !card.id.hasPrefix("daily-"), session.result == nil {
                    Button { reporting = true } label: {
                        Image(systemName: "flag").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.secondary)
                            .frame(width: 36, height: 36).glassCapsule().hitTarget()
                    }.buttonStyle(PressStyle(scale: 0.92)).accessibilityLabel("Signaler cette carte")
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(session.phase == .playing ? Format.clock(session.result?.timeMs ?? session.elapsedMs) : "0:00")
                        .scaledFont(14, .bold).monospacedDigit().foregroundStyle(Palette.foreground)
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
            Text(session.ranked ? "Chrono officiel. Les erreurs ne terminent pas la partie." : "Les erreurs ne terminent pas la partie.")
                .scaledFont(12).foregroundStyle(Palette.tertiary).padding(.top, 6)
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
            }.buttonStyle(PressStyle()).disabled(session.usedHint || session.result != nil).opacity(session.usedHint ? 0.5 : 1)
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
        session.answer += letter
    }
    private func delete() {
        guard !session.answer.isEmpty else { return }
        session.answer.removeLast()
    }
    private func submit() {
        guard session.result == nil else { return }
        guard WordEngine.normalize(session.answer).count >= 1 else { shake(); return }
        let before = session.wrongAnswers
        session.submit(mode: mode, state: state)
        if session.result != nil {
            finishedHere = true
        } else if session.wrongAnswers > before {
            shake()
            session.answer = ""
            if let feedback = session.feedback { AccessibilityNotification.Announcement(feedback).post() }
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
                let word = card.wordFull.uppercased()
                HStack(spacing: 0) {
                    ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                        let vowel = Vowels.contains(character)
                        Text(String(character))
                            .foregroundStyle(vowel ? Palette.accent : Palette.foreground)
                            .shadow(color: vowel ? Palette.accent.opacity(0.6) : .clear, radius: 12)
                            .scaleEffect(vowel && !revealed ? 0.01 : 1)
                            .opacity(vowel && !revealed ? 0 : 1)
                            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.5).delay(0.38 + Double(index) * 0.13), value: revealed)
                    }
                }
                .font(.system(size: 42, weight: .heavy)).tracking(2.5).lineLimit(1).minimumScaleFactor(0.4)
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
            HStack(spacing: 10) {
                ShareLink(item: mode == .daily ? ShareText.daily(result, card: card) : ShareText.classic(result, card: card)) {
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
        .onAppear { revealed = true }
    }

    /// Only real numbers: the percentile appears once the server has ranked the result.
    @ViewBuilder private var officialLine: some View {
        if pending {
            Label("Validation du temps officiel…", systemImage: "clock.arrow.circlepath").scaledFont(13, .semibold).foregroundStyle(Palette.secondary)
        } else if let standing, result.correct, let percent = standing.beatenPercent {
            VStack(spacing: 2) {
                Text("Plus rapide que \(percent) % des joueurs").scaledFont(15, .semibold).foregroundStyle(Palette.mint)
                if let rank = standing.rank {
                    Text(Format.ordinal(rank) + " sur \(standing.players) aujourd’hui").scaledFont(13).foregroundStyle(Palette.secondary)
                }
            }.accessibilityElement(children: .combine)
        } else if let standing, result.correct, standing.players <= 1 {
            Label("Premier joueur à trouver aujourd’hui", systemImage: "trophy").scaledFont(13, .semibold).foregroundStyle(Palette.mint)
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
            Button("Valider") { Haptics.selection(); submit() }
                .buttonStyle(PrimaryPillStyle(height: 48)).padding(.horizontal, 4).padding(.top, 2)
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
        Button { UISelectionFeedbackGenerator().selectionChanged(); action() } label: {
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

private struct Caret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 2).fill(Palette.foreground).frame(width: 2.5, height: 30).opacity(visible ? 1 : 0).padding(.leading, 2)
        }
    }
}

private struct Shake: GeometryEffect {
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
