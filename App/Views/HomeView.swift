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
        state.progress.dailyStarted[todayKey].flatMap { id in SeedCards.all.first { $0.id == id } }
    }
    private var level: (number: Int, into: Int) { (state.progress.score / 1000 + 1, state.progress.score % 1000) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                dailyCard
                classicCard
                Label(state.cloud == nil ? "Progression enregistrée sur cet iPhone" : "Connecté · scores locaux d’entraînement", systemImage: "checkmark.shield")
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bonjour,").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                Text(state.progress.username).font(.system(size: 30, weight: .bold)).tracking(-0.6).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 12)
            let streak = state.progress.streak()
            HStack(spacing: 8) {
                Circle().fill(Palette.accent).frame(width: 8, height: 8).shadow(color: Palette.accent, radius: 5)
                Text("\(streak) jour\(streak > 1 ? "s" : "")").font(.system(size: 14, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 14).frame(height: 36).glassCapsule()
            .accessibilityElement(children: .combine).accessibilityLabel("Série quotidienne : \(streak) jours")
            AvatarView(name: state.progress.username, colorIndex: avatar, size: 40)
        }.padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 4)
    }

    private var dailyCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionKicker(text: "Mot du jour", color: Palette.accent).accessibilityLabel("Mot du jour")
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))))
                    .font(.system(size: 13)).foregroundStyle(Palette.tertiary)
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
                Rectangle().fill(Palette.accent).frame(width: 36, height: 1.5).padding(.vertical, 18)
                Text(consonants == nil ? "Un mot, un indice, un chrono. À vous de jouer." : "Votre chrono tourne. Reprenez la partie.")
                    .font(Typo.serifItalic(21)).multilineTextAlignment(.center)
                Text("Un seul essai par jour, enregistré sur cet iPhone").font(.system(size: 13)).foregroundStyle(Palette.tertiary).padding(.top, 8)
                Button(consonants == nil ? "Jouer" : "Reprendre") { Haptics.selection(); play(GameRoute(mode: .daily)) }
                    .buttonStyle(PrimaryPillStyle(height: 54)).padding(.top, 20)
            }
        }.glassCard(radius: 34, padding: 20).padding(.top, 2)
    }

    @ViewBuilder private func dailyDone(_ attempt: Attempt) -> some View {
        let card = SeedCards.all.first { $0.id == attempt.cardID }
        HighlightedWord(word: (card?.wordFull ?? "").uppercased(), font: .system(size: 34, weight: .heavy)).tracking(2.7)
            .padding(.top, 22).padding(.bottom, 4)
        Text(attempt.correct ? "Trouvé en \(Format.clock(attempt.timeMs)) · +\(attempt.points) pts" : "Raté. Un nouveau mot arrive à minuit.")
            .font(.system(size: 15)).foregroundStyle(Palette.secondary)
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 0) {
                    Text("PROCHAIN MOT").font(.system(size: 11)).tracking(0.9).foregroundStyle(Palette.tertiary)
                    Text(countdown(from: context.date)).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.fill1))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
            ShareLink(item: ShareText.daily(attempt, card: card)) {
                Text("Partager").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.foreground)
                    .frame(width: 120, height: 54)
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
                Text("\(state.progress.correctAnswers) mots trouvés").font(.system(size: 13)).foregroundStyle(Palette.tertiary)
            }
            Text("Jouez sans limite").font(.system(size: 22, weight: .bold)).tracking(-0.2).padding(.top, 10)
            HStack {
                Text("Niveau \(level.number)")
                Spacer()
                Text("\(1000 - level.into) pts avant le niveau \(level.number + 1)")
            }.font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 16)
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
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.foreground)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(Palette.fill1))
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
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
