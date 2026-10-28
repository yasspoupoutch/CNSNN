import SwiftUI
import CNSNNCore

/// Admins only: the anonymous attendance of the last two weeks (`stats/{day}`, see Core/Usage.swift).
struct AttendanceView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var days: [DayUsage] = []
    @State private var loaded = false
    @State private var message: String?
    private static let modes = [("daily", "Mot du jour"), ("classic", "Classique"), ("sprint", "Sprint"), ("survival", "Survie"), ("duo", "Double sens"), ("challenge", "Défis")]
    var body: some View {
        List {
            if let message { Section { Text(message) } }
            if let today = days.first(where: { $0.day == DailySchedule.key() }) ?? (loaded ? DayUsage(day: DailySchedule.key(), counts: [:]) : nil) {
                summary("Aujourd’hui", today.counts)
            }
            if loaded { summary("7 derniers jours", total(days.filter { $0.day >= DailySchedule.key(Date().addingTimeInterval(-6 * 86_400)) })) }
            Section {
                if days.isEmpty { Text(loaded ? "Aucun chiffre pour l’instant." : "Chargement…").foregroundStyle(.secondary) }
                ForEach(days) { day in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Self.label(day.day))
                        Spacer()
                        Text(line(day.counts)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Par jour") } footer: {
                Text("Comptés par téléphone, sans nom ni identifiant : un joueur sur deux appareils compte deux fois. Les téléphones sans la dernière version de l’app ne sont pas comptés.")
            }
        }
        .navigationTitle("Fréquentation")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .task { await refresh() }
        .refreshable { await refresh() }
    }
    private func summary(_ title: String, _ c: [String: Int]) -> some View {
        Section {
            row("Joueurs", c["players"], detail: "dont \(c["newPlayers"] ?? 0) nouveaux")
            row("Ouvertures de l’app", (c["opensIos"] ?? 0) + (c["opensAndroid"] ?? 0), detail: "iPhone \(c["opensIos"] ?? 0) · Android \(c["opensAndroid"] ?? 0)")
            row("Nouveaux appareils", (c["newIos"] ?? 0) + (c["newAndroid"] ?? 0), detail: "dont \(max(0, (c["newIos"] ?? 0) + (c["newAndroid"] ?? 0) - (c["newPlayers"] ?? 0))) sans partie")
            row("Parties", Self.modes.reduce(0) { $0 + (c[$1.0] ?? 0) }, detail: nil)
            ForEach(Self.modes, id: \.0) { mode in row("   " + mode.1, c[mode.0], detail: nil) }
        } header: { Text(title) }
    }
    private func row(_ title: String, _ value: Int?, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(Format.number(value ?? 0)).font(.body.monospacedDigit().weight(.semibold))
        }
    }
    private func line(_ c: [String: Int]) -> String {
        let games = Self.modes.reduce(0) { $0 + (c[$1.0] ?? 0) }
        return "\(c["players"] ?? 0) joueur\((c["players"] ?? 0) > 1 ? "s" : "") · \(games) partie\(games > 1 ? "s" : "")"
    }
    private func total(_ list: [DayUsage]) -> [String: Int] {
        list.reduce(into: [:]) { sum, day in for (k, v) in day.counts { sum[k, default: 0] += v } }
    }
    /// "sam. 24 oct." for 2026-10-24.
    private static func label(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = DailySchedule.calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }
    private func refresh() async {
        do {
            guard let cloud = state.cloud else { message = "Le serveur n’est pas configuré."; return }
            guard try await cloud.isAdmin() else { message = "Accès administrateur requis."; return }
            days = try await cloud.usage(since: DailySchedule.key(Date().addingTimeInterval(-13 * 86_400)))
            loaded = true; message = nil
        } catch { message = CloudError.message(error) }
    }
}
