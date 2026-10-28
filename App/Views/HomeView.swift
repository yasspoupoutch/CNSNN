import SwiftUI
import CNSNNCore

struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var category: CNSNNCore.Category?
    @State private var difficulty: Difficulty?
    @State private var showClassic = false
    @State private var pending: GameRoute?
    @State private var showChallenges = false
    /// The missed day the player tapped in the week strip, asked before its clock starts.
    @State private var catchUpChoice: String?
    /// Days of this week played on another phone, found on the server (day to found).
    @State private var playedElsewhere: [String: Bool] = [:]
    @Environment(\.scenePhase) private var scenePhase
    /// Bumped when a saved game changes, so "Partie en cours" stays right.
    @State private var savedRuns = ModeRunStore.inProgress()
    @Environment(\.dynamicTypeSize) private var typeSize
    var play: (GameRoute) -> Void

    /// The day on screen, moved on at midnight and whenever the app comes back (a notification tap
    /// the next morning), so yesterday's found word never stays up.
    @State private var todayKey = DailySchedule.key()
    private var todayAttempt: Attempt? { state.progress.attempts.first { $0.dailyKey == todayKey } }
    /// Only reveal the consonants once the daily card is locked, so the clock is already running.
    private var startedDailyCard: Card? {
        state.progress.dailyStarted[todayKey].flatMap { state.card(id: $0) }
    }
    private var level: (number: Int, into: Int) { (state.progress.level, state.progress.levelInto) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                // The free Firestore quota is used up for today: one calm line instead of errors everywhere.
                if state.isServerFull {
                    Label(CloudError.serverFull.errorDescription ?? "", systemImage: "hourglass")
                        .scaledFont(14).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .glassPanel(radius: 24, padding: 16).accessibilityIdentifier("home.serverFull")
                }
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
        .sheet(isPresented: $showChallenges, onDismiss: {
            if let route = pending { pending = nil; play(route) }
        }) {
            ChallengeSheet { pending = GameRoute(mode: .classic, challenge: $0) }
                .presentationDetents([.large]).presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .confirmationDialog(catchUpChoice.map { "Rattraper le mot du " + Format.weekday($0) + " ?" } ?? "",
                            isPresented: Binding(get: { catchUpChoice != nil }, set: { if !$0 { catchUpChoice = nil } }),
                            titleVisibility: .visible, presenting: catchUpChoice) { day in
            Button("Jouer") { play(GameRoute(mode: .daily, catchUpDay: day)) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Il compte au classement de la semaine avec 5 minutes en plus. Le chrono démarre dès l’ouverture.")
        }
        .task(id: "\(todayKey)|\(state.uid ?? "")") {
            // A missed day may have been played on another phone.
            guard let cloud = state.cloud, let uid = state.uid else { return }
            for day in state.catchUpDays() where day.status == .open && playedElsewhere[day.key] == nil {
                if let result = try? await cloud.dailyResult(uid: uid, day: day.key) { playedElsewhere[day.key] = result.correct }
            }
        }
        // "Défier un ami" on the daily result: opens the sheet once the game has closed.
        .onChange(of: state.challengeRequest) { _, _ in
            Task { try? await Task.sleep(for: .seconds(0.7)); showChallenges = true }
        }
        // A challenge link opened the app: the sheet joins it as soon as the player is connected.
        .onChange(of: state.inviteCode) { _, code in if code != nil { showChallenges = true } }
        .task(id: state.uid) {
            if state.inviteCode != nil { showChallenges = true }
            await state.refreshChallenges()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            todayKey = DailySchedule.key()
            Task { await state.refreshChallenges() }
        }
        .task(id: todayKey) {
            // Wakes up just after midnight to show the new word, then waits for the next day.
            let calendar = DailySchedule.calendar
            let now = Date()
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(now) + 1)))
            if !Task.isCancelled { todayKey = DailySchedule.key() }
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

    /// One card for the day: the kicker with Classement and Partager at the top right, the consonants
    /// (or the found word) with Jouer, then this week's 7 days at the bottom.
    private var dailyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                dailyKicker(done: todayAttempt?.correct == true)
                Spacer(minLength: 4)
                if state.cloud != nil || todayAttempt != nil {
                    Button { Haptics.selection(); state.leaderboardRequest += 1 } label: {
                        podiumIcon
                    }.buttonStyle(PressStyle()).accessibilityLabel("Classement")
                }
                if let attempt = todayAttempt {
                    ShareResultLink(attempt: attempt, card: state.card(id: attempt.cardID), mode: .daily) {
                        cornerIcon("square.and.arrow.up")
                    }.buttonStyle(PressStyle()).accessibilityLabel("Partager")
                }
            }
            if let attempt = todayAttempt {
                dailyDone(attempt)
            } else {
                let consonants = startedDailyCard?.wordNoVowels
                HStack(alignment: .center, spacing: 14) {
                    Text(consonants ?? "· · ·")
                        .font(Typo.serif(consonants == nil ? 34 : 46)).tracking(consonants == nil ? 6 : 3)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .foregroundStyle(consonants == nil ? Palette.tertiary : Palette.foreground)
                        .accessibilityLabel(consonants.map { "Consonnes : " + $0.map(String.init).joined(separator: ", ") } ?? "Mot masqué")
                    Spacer(minLength: 4)
                    Button(consonants == nil ? "Jouer" : "Reprendre") { Haptics.selection(); play(GameRoute(mode: .daily)) }
                        .buttonStyle(PrimaryPillStyle(height: 54)).frame(width: 128)
                        .tutorialTarget(.play)
                }.padding(.top, 4)
                Text(consonants == nil ? "Un mot, un indice, un chrono." : "Votre chrono tourne. Reprenez la partie.")
                    .font(Typo.serifItalic(18)).foregroundStyle(Palette.secondary).padding(.top, 8)
                    .accessibilityLabel((consonants == nil ? "Un mot, un indice, un chrono." : "Votre chrono tourne.")
                        + (state.uid == nil ? " Une seule partie par jour, enregistrée sur cet iPhone." : " Le même mot pour tous, une seule partie classée par jour."))
            }
            if state.cloud != nil || ScreenshotDemo.isActive {
                Rectangle().fill(Palette.line).frame(height: 1).padding(.top, 16).padding(.bottom, 12)
                weekRow
            }
        }.glassCard(radius: 32, padding: 20).tutorialTarget(.daily).padding(.top, 2)
    }

    private func cornerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.foreground)
            .frame(width: 36, height: 36).glassCapsule().frame(minWidth: 44, minHeight: 44)
    }

    /// A podium (2nd, 1st, 3rd), which reads as a ranking better than bars: SF Symbols has none.
    private var podiumIcon: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach([10.0, 15.0, 7.0], id: \.self) { height in
                UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5, style: .continuous)
                    .frame(width: 5, height: height)
            }
        }
        .foregroundStyle(Palette.foreground)
        .frame(width: 36, height: 36).glassCapsule().frame(minWidth: 44, minHeight: 44)
    }

    /// This week's daily words, Monday to Sunday, like the 7 days in Stats: a green check for a found word,
    /// a red cross for a lost one. A missed day can be caught up: it counts in the week with 5 minutes more.
    private var weekRow: some View {
        let days = state.dailyWeek().map { day in playedElsewhere[day.key].map { CatchUp.Day(key: day.key, status: .played(found: $0)) } ?? day }
        let letters = ["L", "M", "M", "J", "V", "S", "D"]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    Button { tap(day) } label: {
                        VStack(spacing: 4) {
                            weekCell(day.status)
                            Text(letters[index]).scaledFont(11, day.status == .today ? .bold : .regular)
                                .foregroundStyle(day.status == .today ? Palette.foreground : Palette.tertiary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle(scale: 0.92))
                    .allowsHitTesting(playable(day.status))
                    .accessibilityLabel(Format.day(day.key) + " : " + spoken(day.status))
                    .accessibilityIdentifier("week.\(day.key)")
                }
            }
            Text(weekLine(days)).scaledFont(12).foregroundStyle(Palette.tertiary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func weekCell(_ status: CatchUp.Status) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let (color, symbol, ink): (Color, String?, Color) = switch status {
        case .played(true): (Palette.mint, "checkmark", Palette.ink)
        case .played(false): (Palette.red, "xmark", Palette.ink)
        case .open: (Palette.fill1, "play.fill", Palette.foreground)
        case .later: (Palette.fill1, "clock", Palette.tertiary)
        case .today, .coming: (Palette.fill1, nil, Palette.foreground)
        }
        return shape.fill(color).frame(width: 30, height: 30)
            .overlay(shape.strokeBorder(status == .today ? Palette.foreground : Palette.line, lineWidth: status == .today ? 1.5 : 1))
            .overlay {
                // A symbol as well as the colour, so the week reads without colour vision.
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(ink) }
            }
            .opacity(status == .coming ? 0.45 : 1)
    }

    private func playable(_ status: CatchUp.Status) -> Bool {
        switch status { case .open, .today: true; default: false }
    }
    private func tap(_ day: CatchUp.Day) {
        Haptics.selection()
        switch day.status {
        case .open: catchUpChoice = day.key
        case .today: play(GameRoute(mode: .daily))
        default: break
        }
    }
    private func weekLine(_ days: [CatchUp.Day]) -> String {
        let open = days.filter { $0.status == .open }.count
        if open > 0 { return "\(open) jour\(open > 1 ? "s" : "") à rattraper (+5 min)" }
        for day in days { if case .later(let date) = day.status { return "À rattraper dès " + Format.hour(date) } }
        let found = days.filter { $0.status == .played(found: true) }.count
        return "\(found) mot\(found > 1 ? "s" : "") trouvé\(found > 1 ? "s" : "")"
    }
    private func spoken(_ status: CatchUp.Status) -> String {
        switch status {
        case .played(true): "trouvé"
        case .played(false): "raté"
        case .open: "manqué, à rattraper avec 5 minutes en plus"
        case .later(let date): "manqué, à rattraper dès " + Format.hour(date)
        case .today: "aujourd’hui, à jouer"
        case .coming: "à venir"
        }
    }

    private func dailyKicker(done: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionKicker(text: "Mot du jour", color: Palette.foreground).fixedSize().accessibilityLabel("Mot du jour")
            if done {
                Label("trouvé", systemImage: "checkmark").scaledFont(12, .semibold).foregroundStyle(Palette.mint).labelStyle(.titleAndIcon).fixedSize()
            } else {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .scaledFont(13).foregroundStyle(Palette.tertiary).lineLimit(1)
            }
        }
    }

    /// The word on the whole width (shrunk if long), then the time and the countdown.
    @ViewBuilder private func dailyDone(_ attempt: Attempt) -> some View {
        let card = state.card(id: attempt.cardID)
        VStack(alignment: .leading, spacing: 4) {
            HighlightedWord(word: (card?.wordFull ?? "").uppercased(), font: Typo.serif(40)).tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // A day counts 10 minutes at most: past that, the real time stays here with what the ranking counts.
            Text(attempt.correct ? Format.clock(attempt.timeMs) + (attempt.timeMs >= DailyScore.missedMs ? " · compté " + Format.clock(DailyScore.missedMs) + " au classement" : "") : "Raté cette fois")
                .scaledFont(13).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Prochain mot dans " + countdown(from: context.date))
                    .scaledFont(12).monospacedDigit().foregroundStyle(Palette.tertiary).lineLimit(2).minimumScaleFactor(0.8)
            }
        }.padding(.top, 4)
    }

    // MARK: Modes

    /// Classique, Sprint, Survie and Double sens: two columns, one on the largest text sizes.
    private var modes: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return VStack(alignment: .leading, spacing: 12) {
            SectionKicker(text: "Jouer aussi").padding(.leading, 4).padding(.top, 6)
            ChallengeTile(open: { showChallenges = true }, play: { play(GameRoute(mode: .classic, challenge: $0)) })
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
        return "Record " + ModeRecordText.main(mode, records)
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
                Text("\(ClassicLevel.wordsPerLevel - level.into) mots avant le niveau \(level.number + 1)")
            }.scaledFont(13).foregroundStyle(Palette.secondary).padding(.top, 16)
            ProgressBar(value: Double(level.into) / Double(ClassicLevel.wordsPerLevel), color: Palette.foreground).padding(.top, 8)
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
        if state.uid == nil { return state.cloud == nil ? "Progression enregistrée sur cet iPhone" : (state.isServerFull ? "Serveur plein" : "Hors connexion") + " · progression gardée sur cet iPhone" }
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
        let outcome = attempt.correct ? "trouvé en \(Format.clock(attempt.timeMs))" : "raté"
        return "CNSNN · Mot du jour \(day) : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "") + invitation
    }
    static func classic(_ attempt: Attempt, card: Card?) -> String {
        let outcome = attempt.correct ? "trouvé en \(Format.clock(attempt.timeMs))" : "raté"
        return "CNSNN · Classique : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "") + invitation
    }
    /// Every share says where to get the game.
    static let invitation = "\nJouez aussi : " + Site.appStore.absoluteString
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
        let outcome = attempt.correct ? "Trouvé en \(Format.clock(attempt.timeMs))" : "Raté cette fois"
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
