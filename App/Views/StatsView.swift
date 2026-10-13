import SwiftUI
import CNSNNCore

struct StatsView: View {
    @Environment(AppState.self) private var state
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var progress: CNSNNCore.Progress { state.progress }
    @State private var page = 0
    @State private var refreshToken = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Statistiques").scaledFont(34, .bold).tracking(-0.6)
                    .padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Chip(title: "Mes stats", selected: page == 0) { page = 0 }
                    Chip(title: "Classement", selected: page == 1) { page = 1 }
                }
                if page == 1 { LeaderboardView(refreshToken: refreshToken) } else { mine }
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
            .refreshable { refreshToken += 1; await state.refreshOfficial() }
            .animation(CNSNNTheme.ease, value: page)
    }

    @ViewBuilder private var mine: some View {
        if let entry = state.official { officialCard(entry) }
        pointsCard
        LazyVGrid(columns: columns, spacing: 12) {
            tile("\(progress.attempts.count)", "Cartes jouées")
            tile("\(Int(progress.successRate * 100)) %", "Réussite · \(progress.correctAnswers) trouvés")
            tile("\(state.official?.currentStreak() ?? progress.streak())", "Série quotidienne")
            tile("\(progress.dailyWins)", "Défis réussis")
            tile(time(progress.bestTimeMs), "Meilleur temps")
            tile(time(progress.averageTimeMs), "Temps moyen")
        }
        weekCard
        if progress.attempts.isEmpty {
            Text("Votre première partie lance l’histoire.").scaledFont(15).foregroundStyle(Palette.secondary).padding(.horizontal, 2)
        }
    }

    /// Numbers from the server's leaderboard: only Mots du jour count here.
    private func officialCard(_ entry: LeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionKicker(text: "Mot du jour · officiel", color: Palette.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Format.number(entry.points)).scaledFont(34, .heavy).monospacedDigit()
                Text("points").scaledFont(15).foregroundStyle(Palette.secondary)
                Spacer()
            }
            HStack(spacing: 0) {
                officialStat("\(entry.currentStreak())", "série")
                officialStat("\(entry.bestStreak)", "record de série")
                officialStat("\(Int((entry.successRate * 100).rounded())) %", "réussite")
                officialStat(Format.seconds(entry.bestTimeMs), "meilleur temps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 32, padding: 20)
        .accessibilityElement(children: .combine)
    }
    private func officialStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).scaledFont(17, .bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(11).foregroundStyle(Palette.tertiary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pointsCard: some View {
        let level = progress.score / 1000 + 1, into = progress.score % 1000
        return VStack(alignment: .leading, spacing: 0) {
            Text(state.official == nil ? "Vos points" : "Tous vos points, entraînement compris").scaledFont(13).foregroundStyle(Palette.secondary)
            Text(Format.number(progress.score)).font(.system(size: 54, weight: .heavy)).tracking(-1.6).monospacedDigit()
                .foregroundStyle(Palette.foreground).lineLimit(1).minimumScaleFactor(0.5)
            HStack {
                Text("Niveau \(level)")
                Spacer()
                Text("\(1000 - into) pts avant le niveau \(level + 1)")
            }.scaledFont(13).foregroundStyle(Palette.secondary).padding(.top, 12)
            ProgressBar(value: Double(into) / 1000, color: Palette.foreground).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 32, padding: 22)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).scaledFont(28, .bold).tracking(-0.5).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).scaledFont(13).foregroundStyle(Palette.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .glassPanel(radius: 24, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mots du jour · 7 derniers jours").scaledFont(15, .semibold)
            HStack {
                ForEach(week, id: \.key) { day in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(day.color)
                            .frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                            .overlay {
                                // A symbol as well as the colour, so the result reads without colour vision.
                                if let symbol = day.symbol {
                                    Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.ink)
                                }
                            }
                        Text(day.letter).scaledFont(12).foregroundStyle(Palette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.key) : \(day.status)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 28, padding: 20)
    }

    private func time(_ value: Int?) -> String { Format.seconds(value) }

    private var week: [(key: String, letter: String, color: Color, symbol: String?, status: String)] {
        let calendar = DailySchedule.calendar
        let letters = ["D", "L", "M", "M", "J", "V", "S"]
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))!
            let key = DailySchedule.key(day)
            let attempt = progress.attempts.first { $0.dailyKey == key }
            let letter = letters[calendar.component(.weekday, from: day) - 1]
            switch attempt?.correct {
            case true?: return (key, letter, Palette.mint, "checkmark", "trouvé")
            case false?: return (key, letter, Palette.red, "xmark", "raté")
            case nil: return (key, letter, Palette.fill1, nil, "non joué")
            }
        }
    }
}
