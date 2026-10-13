import WidgetKit
import SwiftUI
import CNSNNCore

/// Home screen widget: today's Mot du jour (to play, found or missed) and the daily streak.
/// The app writes a Glance into the shared App Group; without it, the widget still shows the day's difficulty.
@main struct CNSNNWidgetBundle: WidgetBundle {
    var body: some Widget { DailyWidget() }
}

struct DailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CNSNNDaily", provider: DailyProvider()) { entry in
            DailyWidgetView(entry: entry)
        }
        .configurationDisplayName("Mot du jour")
        .description("Votre série et le mot du jour à trouver.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DailyEntry: TimelineEntry {
    let date: Date
    let glance: Glance?
    static let sample = DailyEntry(date: Date(), glance: Glance(streak: 4, lastWinKey: DailySchedule.key(DailySchedule.previousDay(Date()))))
}

struct DailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (DailyEntry) -> Void) {
        completion(context.isPreview ? .sample : DailyEntry(date: Date(), glance: Glance.load()))
    }
    /// One entry now and one at the next Paris midnight, when a new word arrives.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyEntry>) -> Void) {
        let now = Date(), glance = Glance.load(), midnight = Glance.nextDay(after: now)
        let entries = [DailyEntry(date: now, glance: glance), DailyEntry(date: midnight, glance: glance)]
        completion(Timeline(entries: entries, policy: .after(Glance.nextDay(after: midnight))))
    }
}

private enum WidgetPalette {
    static let top = Color(red: 0.16, green: 0.12, blue: 0.42)
    static let bottom = Color(red: 0.05, green: 0.05, blue: 0.12)
    static let gold = Color(red: 0.98, green: 0.80, blue: 0.36)
    static let mint = Color(red: 0.352, green: 0.902, blue: 0.775)
    static let secondary = Color.white.opacity(0.72)
}

struct DailyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyEntry

    private var day: String { DailySchedule.key(entry.date) }
    private var played: Bool { entry.glance?.playedToday(entry.date) ?? false }
    private var streak: Int { entry.glance?.currentStreak(entry.date) ?? 0 }
    private var difficulty: String { DailySchedule.difficulty(forKey: day)?.rawValue ?? "" }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MOT DU JOUR").font(.system(size: 11, weight: .bold)).tracking(1.2).foregroundStyle(WidgetPalette.secondary)
                Text(status).font(.system(size: family == .systemSmall ? 22 : 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(statusColor).minimumScaleFactor(0.6).lineLimit(2)
                Text(detail).font(.system(size: 12, weight: .medium)).foregroundStyle(WidgetPalette.secondary).lineLimit(2)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? WidgetPalette.gold : WidgetPalette.secondary)
                    Text("\(streak) jour\(streak > 1 ? "s" : "")").monospacedDigit()
                }.font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            if family == .systemMedium {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Prochain mot").font(.system(size: 11, weight: .semibold)).foregroundStyle(WidgetPalette.secondary)
                    Text(Glance.nextDay(after: entry.date), style: .relative)
                        .font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(.white).multilineTextAlignment(.trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [WidgetPalette.top, WidgetPalette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var status: String {
        guard played, let glance = entry.glance else { return "À jouer" }
        return glance.lastDailyCorrect ? "Trouvé" : "Raté"
    }
    private var statusColor: Color { played ? (entry.glance?.lastDailyCorrect == true ? WidgetPalette.mint : WidgetPalette.secondary) : WidgetPalette.gold }
    private var detail: String {
        if played, let glance = entry.glance, glance.lastDailyCorrect {
            let seconds = glance.lastDailyTimeMs / 1000
            return "En \(seconds / 60):" + String(format: "%02d", seconds % 60)
        }
        if played { return "Revenez demain" }
        return difficulty.isEmpty ? "Un nouveau mot vous attend" : "Difficulté : " + difficulty.lowercased()
    }
}
