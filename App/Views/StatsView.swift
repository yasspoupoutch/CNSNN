import SwiftUI
import Charts
import CNSNNCore

struct StatsView: View {
    @Environment(AppState.self) private var state
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Chaque déclic compte.").font(.largeTitle.weight(.semibold))
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(state.progress.score)").font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("points d’entraînement").foregroundStyle(.secondary)
                    ProgressView(value: Double(state.progress.score % 1000), total: 1000).tint(CNSNNTheme.accent)
                    Text("Niveau \(state.progress.score / 1000 + 1) · prochain palier dans \(1000 - state.progress.score % 1000) points").font(.footnote).foregroundStyle(.secondary)
                }.cnsnnSurface()
                LazyVGrid(columns: columns, spacing: 12) {
                    StatCard(title: "Cartes jouées", value: "\(state.progress.attempts.count)", symbol: "square.stack")
                    StatCard(title: "Bonnes réponses", value: "\(state.progress.correctAnswers)", symbol: "checkmark")
                    StatCard(title: "Réussite", value: "\(Int(state.progress.successRate * 100)) %", symbol: "scope")
                    StatCard(title: "Meilleur temps", value: time(state.progress.bestTimeMs), symbol: "bolt")
                    StatCard(title: "Temps moyen", value: time(state.progress.averageTimeMs), symbol: "timer")
                    StatCard(title: "Défis réussis", value: "\(state.progress.dailyWins)", symbol: "sun.max")
                    StatCard(title: "Série quotidienne", value: "\(state.progress.streak()) j", symbol: "flame")
                }
                if !state.progress.attempts.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tes sept derniers jours").font(.headline)
                        Chart(week, id: \.date) { entry in
                            BarMark(x: .value("Jour", entry.date, unit: .day), y: .value("Points", entry.points)).foregroundStyle(CNSNNTheme.accent).cornerRadius(4)
                        }.frame(height: 140).chartYAxis(.hidden)
                            .accessibilityLabel("Points obtenus sur les sept derniers jours")
                    }.cnsnnSurface()
                } else {
                    Text("Ta première partie lance l’histoire.").foregroundStyle(.secondary)
                }
            }.padding(24)
        }.background(CNSNNTheme.background).navigationTitle("Stats").navigationBarTitleDisplayMode(.inline)
    }
    private func time(_ value: Int?) -> String { value.map { String(format: "%.1f s", Double($0) / 1000) } ?? "—" }
    private var week: [(date: Date, points: Int)] {
        let calendar = DailySchedule.calendar
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))!
            return (day, state.progress.attempts.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.points })
        }
    }
}
