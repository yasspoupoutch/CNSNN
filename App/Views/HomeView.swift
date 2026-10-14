import SwiftUI
import CNSNNCore

struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var category: CNSNNCore.Category?
    @State private var difficulty: Difficulty?
    @State private var showClassic = false
    @State private var pending: GameRoute?
    /// Bumped when a saved game changes, so "Partie en cours" stays right.
    @State private var savedRuns = ModeRunStore.inProgress()
    @Environment(\.dynamicTypeSize) private var typeSize
    var play: (GameRoute) -> Void

    private var todayKey: String { DailySchedule.key() }
    private var todayAttempt: Attempt? { state.progress.attempts.first { $0.dailyKey == todayKey } }
    /// Only reveal the consonants once the daily card is locked, so the clock is already running.
    private var startedDailyCard: Card? {
        state.progress.dailyStarted[todayKey].flatMap { state.card(id: $0) }
    }
    private var level: (number: Int, into: Int) { (state.progress.score / 1000 + 1, state.progress.score % 1000) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                dailyCard
                modes
                Label(syncLabel, systemImage: state.uid == nil ? "iphone" : "checkmark.icloud")
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let runs = ModeRunStore.inProgress()
            if runs != savedRuns { savedRuns = runs }
        }
        .sheet(isPresented: $showClassic, onDismiss: {
            if let route = pending { pending = nil; play(route) }
        }) {
            classicSheet.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bonjour,").scaledFont(15).foregroundStyle(Palette.secondary)
                Text(state.progress.username).scaledFont(30, .bold).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 12)
            let streak = state.official?.currentStreak() ?? state.progress.streak()
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary)
                    .symbolEffect(.bounce, value: streak)
                Text("\(streak) jour\(streak > 1 ? "s" : "")").scaledFont(14, .semibold).monospacedDigit()
            }
            .padding(.horizontal, 14).frame(minHeight: 36).glassCapsule()
            .accessibilityElement(children: .combine).accessibilityLabel("Série quotidienne : \(streak) jours")
            AvatarView(name: state.progress.username, colorIndex: avatar, size: 40)
        }.padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 4)
    }

    private var dailyCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionKicker(text: "Mot du jour", color: Palette.foreground).accessibilityLabel("Mot du jour")
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .scaledFont(13).foregroundStyle(Palette.tertiary)
            }
            if let attempt = todayAttempt {
                dailyDone(attempt)
            } else {
                let consonants = startedDailyCard?.wordNoVowels
                Text(consonants ?? "· · ·")
                    .font(Typo.serif(100)).tracking(5).lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(consonants == nil ? Palette.tertiary : Palette.foreground)
                    .padding(.top, 34).padding(.bottom, 6)
                    .accessibilityLabel(consonants.map { "Consonnes : " + $0.map(String.init).joined(separator: ", ") } ?? "Mot masqué")
                Rectangle().fill(Palette.tertiary).frame(width: 36, height: 1.5).padding(.vertical, 18)
                Text(consonants == nil ? "Un mot, un indice, un chrono. À vous de jouer." : "Votre chrono tourne. Reprenez la partie.")
                    .font(Typo.serifItalic(21)).multilineTextAlignment(.center)
                Text(state.uid == nil ? "Une seule partie par jour, enregistrée sur cet iPhone" : "Le même mot pour tous, une seule partie classée par jour")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 8)
                Button(consonants == nil ? "Jouer" : "Reprendre") { Haptics.selection(); play(GameRoute(mode: .daily)) }
                    .buttonStyle(PrimaryPillStyle(height: 58)).padding(.top, 24)
            }
        }.glassCard(radius: 38, padding: 24).padding(.top, 2)
    }

    @ViewBuilder private func dailyDone(_ attempt: Attempt) -> some View {
        let card = state.card(id: attempt.cardID)
        HighlightedWord(word: (card?.wordFull ?? "").uppercased(), font: .system(size: 34, weight: .heavy)).tracking(2.7)
            .padding(.top, 22).padding(.bottom, 4)
        Text(attempt.correct ? "Trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "Raté. Un nouveau mot arrive à minuit.")
            .scaledFont(15).foregroundStyle(Palette.secondary)
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    Text("PROCHAIN MOT").scaledFont(11).tracking(0.9).foregroundStyle(Palette.tertiary)
                    Text(countdown(from: context.date)).scaledFont(18, .semibold).monospacedDigit()
                }
                .frame(maxWidth: .infinity).frame(minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            ShareResultLink(attempt: attempt, card: card, mode: .daily) {
                Text("Partager").scaledFont(15, .semibold).foregroundStyle(Palette.foreground)
                    .frame(minWidth: 120, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill2))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
            }.buttonStyle(PressStyle())
        }.padding(.top, 20)
    }

    // MARK: Modes

    /// Classique, Sprint, Survie and Double sens: two columns, one on the largest text sizes.
    private var modes: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            SectionKicker(text: "Autres modes").padding(.leading, 4).padding(.top, 6)
            LazyVGrid(columns: columns, spacing: 12) {
                ModeTile(symbol: "infinity", tint: Palette.foreground, title: "Classique", tagline: "Jouez sans limite.",
                         detail: "\(state.progress.correctAnswers) mots trouvés", inProgress: false) {
                    showClassic = true
                }
                ForEach(PlayMode.allCases) { mode in
                    ModeTile(symbol: mode.symbol, tint: mode.tint, title: mode.title, tagline: mode.tagline,
                             detail: recordLine(mode), inProgress: savedRuns.contains(mode)) {
                        play(GameRoute(mode: .classic, play: mode))
                    }
                }
            }
        }
    }

    private func recordLine(_ mode: PlayMode) -> String {
        let records = state.progress.records(mode)
        guard records.total(ModeStat.games) > 0 else { return "Première partie" }
        switch mode {
        case .sprint: return "Record \(Format.number(records.best(ModeStat.score))) pts"
        case .survival: return "Record \(records.best(ModeStat.words)) mots"
        case .duo: return "Record \(Format.number(records.best(ModeStat.score))) pts"
        }
    }

    private var classicSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionKicker(text: "Classique", color: Palette.secondary)
                Spacer()
                Text("\(state.progress.correctAnswers) mots trouvés").scaledFont(13).foregroundStyle(Palette.tertiary)
            }
            Text("Jouez sans limite").scaledFont(24, .bold).tracking(-0.2).padding(.top, 10)
            HStack {
                Text("Niveau \(level.number)")
                Spacer()
                Text("\(1000 - level.into) pts avant le niveau \(level.number + 1)")
            }.scaledFont(13).foregroundStyle(Palette.secondary).padding(.top, 16)
            ProgressBar(value: Double(level.into) / 1000, color: Palette.foreground).padding(.top, 8)
            HStack(spacing: 8) {
                FilterMenu(title: category?.rawValue ?? "Toutes catégories") {
                    Button("Toutes catégories") { category = nil }
                    ForEach(CNSNNCore.Category.allCases) { item in Button(item.rawValue) { category = item } }
                }
                FilterMenu(title: difficulty?.rawValue ?? "Toutes difficultés") {
                    Button("Toutes difficultés") { difficulty = nil }
                    ForEach(Difficulty.allCases) { item in Button(item.rawValue) { difficulty = item } }
                }
            }.padding(.top, 18)
            Spacer(minLength: 20)
            Button("Lancer une partie") {
                Haptics.selection()
                pending = GameRoute(mode: .classic, category: category, difficulty: difficulty)
                showClassic = false
            }.buttonStyle(PrimaryPillStyle(height: 56))
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
    }

    private var syncLabel: String {
        if state.uid == nil { return state.cloud == nil ? "Progression enregistrée sur cet iPhone" : "Hors connexion · progression gardée sur cet iPhone" }
        if state.isAnonymous { return "Sauvegardé en ligne · compte invité" }
        return "Sauvegardé en ligne · " + (state.email ?? "compte permanent")
    }

    private func countdown(from date: Date) -> String {
        let calendar = DailySchedule.calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let seconds = max(0, Int(midnight.timeIntervalSince(date)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}

/// One mode on the home page: a small glyph, its name, its promise and the player's record.
struct ModeTile: View {
    var symbol: String
    var tint: Color
    var title: String
    var tagline: String
    var detail: String
    var inProgress: Bool
    var action: () -> Void
    var body: some View {
        Button { Haptics.selection(); action() } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(tint.opacity(0.12)))
                        .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 1))
                    Spacer(minLength: 4)
                    if inProgress {
                        Text("En cours").scaledFont(11, .semibold).foregroundStyle(Palette.mint)
                            .padding(.horizontal, 8).frame(minHeight: 22)
                            .background(Capsule().fill(Palette.mint.opacity(0.12)))
                    }
                }
                Text(title).scaledFont(18, .bold).tracking(-0.2).foregroundStyle(Palette.foreground).padding(.top, 14)
                Text(tagline).scaledFont(13).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                Spacer(minLength: 12)
                Text(detail).scaledFont(12, .medium).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .glassPanel(radius: 26, padding: 16)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(tagline) \(detail)" + (inProgress ? ". Partie en cours" : ""))
        .accessibilityAddTraits(.isButton)
    }
}

extension PlayMode {
    var symbol: String {
        switch self {
        case .sprint: "bolt.fill"
        case .survival: "heart.fill"
        case .duo: "square.split.2x1.fill"
        }
    }
    /// A quiet tint per mode, only on its glyph.
    var tint: Color {
        switch self {
        case .sprint: Palette.mint
        case .survival: Palette.red
        case .duo: Color(red: 0.62, green: 0.71, blue: 1.0)
        }
    }
    var tagline: String {
        switch self {
        case .sprint: "90 secondes pour battre votre record."
        case .survival: "Jusqu’où irez-vous avec 3 vies ?"
        case .duo: "Deux mots, les mêmes consonnes."
        }
    }
}

struct FilterMenu<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .scaledFont(13, .medium).foregroundStyle(Palette.foreground)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .background(Capsule().fill(Palette.fill1))
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
            .hitTarget()
        }
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill1)
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }.frame(height: 6)
            .accessibilityElement().accessibilityValue("\(Int(value * 100)) %")
    }
}

enum ShareText {
    static func daily(_ attempt: Attempt, card: Card?) -> String {
        let day = attempt.dailyKey ?? DailySchedule.key(attempt.date)
        let outcome = attempt.correct ? "trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "raté"
        return "CNSNN · Mot du jour \(day) : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "") + invitation
    }
    static func classic(_ attempt: Attempt, card: Card?) -> String {
        let outcome = attempt.correct ? "trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "raté"
        return "CNSNN · Classique : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "") + invitation
    }
    /// Every share says where to get the game.
    static let invitation = "\nJouez aussi : " + Site.home.absoluteString
}

/// Picture shared after a game: only the consonants (no spoiler), the result and the wordmark.
struct ShareCard: View {
    var title: String
    var consonants: String
    var outcome: String
    var correct: Bool
    var body: some View {
        VStack(spacing: 0) {
            HighlightedWord(word: "CONSONNE", font: Typo.wordmark(30))
            Text(title.uppercased()).font(.system(size: 13, weight: .bold)).tracking(1.6).foregroundStyle(Palette.secondary).padding(.top, 10)
            Spacer(minLength: 16)
            Text(consonants).font(Typo.serif(72)).tracking(4).foregroundStyle(Palette.foreground).lineLimit(1).minimumScaleFactor(0.3)
            Capsule().fill(Palette.accent).frame(width: 44, height: 4).padding(.top, 18)
            Text(outcome).font(.system(size: 21, weight: .semibold)).foregroundStyle(correct ? Palette.mint : Palette.secondary)
                .multilineTextAlignment(.center).padding(.top, 18)
            Spacer(minLength: 16)
            Text("Trouverez-vous les voyelles ?").font(Typo.serifItalic(21)).foregroundStyle(Palette.accent)
        }
        .padding(34).frame(width: 360, height: 450)
        .background(LinearGradient(colors: [Palette.backgroundTop, Palette.background], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    @MainActor static func image(_ attempt: Attempt, card: Card?, mode: GameMode) -> Image? {
        guard let card else { return nil }
        let title = mode == .daily ? "Mot du jour · " + (attempt.dailyKey ?? DailySchedule.key(attempt.date)) : "Classique"
        let outcome = attempt.correct ? "Trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "Raté cette fois"
        let renderer = ImageRenderer(content: ShareCard(title: title, consonants: card.wordNoVowels, outcome: outcome, correct: attempt.correct))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// Shares the result as a picture with its text, or as text alone if the picture cannot be drawn.
struct ShareResultLink<Label: View>: View {
    var attempt: Attempt
    var card: Card?
    var mode: GameMode
    @ViewBuilder var label: () -> Label
    @State private var image: Image?
    private var text: String { mode == .daily ? ShareText.daily(attempt, card: card) : ShareText.classic(attempt, card: card) }
    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, message: Text(text), preview: SharePreview("CNSNN", image: image), label: label)
            } else {
                ShareLink(item: text, label: label)
            }
        }
        .task(id: attempt.id + (card?.wordNoVowels ?? "")) { image = ShareCard.image(attempt, card: card, mode: mode) }
    }
}
