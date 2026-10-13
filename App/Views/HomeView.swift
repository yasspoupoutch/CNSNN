import SwiftUI
import CNSNNCore

struct HomeView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var category: CNSNNCore.Category?
    @State private var difficulty: Difficulty?
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
                classicCard
                Label(syncLabel, systemImage: state.uid == nil ? "iphone" : "checkmark.icloud")
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
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
                    .font(Typo.serif(84)).tracking(4).lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(consonants == nil ? Palette.tertiary : Palette.foreground)
                    .padding(.top, 26).padding(.bottom, 4)
                    .accessibilityLabel(consonants.map { "Consonnes : " + $0.map(String.init).joined(separator: ", ") } ?? "Mot masqué")
                Rectangle().fill(Palette.tertiary).frame(width: 36, height: 1.5).padding(.vertical, 18)
                Text(consonants == nil ? "Un mot, un indice, un chrono. À vous de jouer." : "Votre chrono tourne. Reprenez la partie.")
                    .font(Typo.serifItalic(21)).multilineTextAlignment(.center)
                Text(state.uid == nil ? "Une seule partie par jour, enregistrée sur cet iPhone" : "Le même mot pour tous, une seule partie classée par jour")
                    .scaledFont(13).foregroundStyle(Palette.tertiary).multilineTextAlignment(.center).padding(.top, 8)
                Button(consonants == nil ? "Jouer" : "Reprendre") { Haptics.selection(); play(GameRoute(mode: .daily)) }
                    .buttonStyle(PrimaryPillStyle(height: 54)).padding(.top, 20)
            }
        }.glassCard(radius: 34, padding: 20).padding(.top, 2)
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
            ShareLink(item: ShareText.daily(attempt, card: card)) {
                Text("Partager").scaledFont(15, .semibold).foregroundStyle(Palette.foreground)
                    .frame(minWidth: 120, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill2))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
            }.buttonStyle(PressStyle())
        }.padding(.top, 20)
    }

    private var classicCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionKicker(text: "Classique", color: Palette.secondary)
                Spacer()
                Text("\(state.progress.correctAnswers) mots trouvés").scaledFont(13).foregroundStyle(Palette.tertiary)
            }
            Text("Jouez sans limite").scaledFont(22, .bold).tracking(-0.2).padding(.top, 10)
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
            }.padding(.top, 16)
            Button("Lancer une partie") { Haptics.selection(); play(GameRoute(mode: .classic, category: category, difficulty: difficulty)) }
                .buttonStyle(GlassPillStyle()).padding(.top, 14)
        }.glassCard(radius: 34, padding: 20)
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
        return "CNSNN · Mot du jour \(day) : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "")
    }
    static func classic(_ attempt: Attempt, card: Card?) -> String {
        let outcome = attempt.correct ? "trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "raté"
        return "CNSNN · Classique : \(outcome)" + (card.map { "\n" + $0.wordNoVowels } ?? "")
    }
}
