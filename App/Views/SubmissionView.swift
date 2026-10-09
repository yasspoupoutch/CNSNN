import SwiftUI
import CNSNNCore

struct SubmissionView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var hint = ""
    @State private var category = CNSNNCore.Category.general
    @State private var difficulty = Difficulty.easy
    @State private var busy = false
    var body: some View {
        Form {
            Section("Ta carte") {
                TextField("Mot complet", text: $word).autocorrectionDisabled()
                TextField("Indice", text: $hint, axis: .vertical).lineLimit(2...4)
                Picker("Catégorie", selection: $category) { ForEach(CNSNNCore.Category.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Difficulté", selection: $difficulty) { ForEach(Difficulty.allCases) { Text($0.rawValue).tag($0) } }
            }
            Section("Aperçu") {
                Text(WordEngine.consonants(word).isEmpty ? "Les consonnes apparaîtront ici" : WordEngine.consonants(word)).font(.title2.monospaced().weight(.bold)).foregroundStyle(CNSNNTheme.accent)
                Text("Y est considéré comme une voyelle. Les espaces, accents et apostrophes sont neutralisés.").font(.footnote)
            }
            Section {
                Button(busy ? "Envoi…" : (state.cloud == nil ? "Enregistrer la proposition localement" : "Envoyer pour validation")) {
                    busy = true
                    Task {
                        let card = Card(id: UUID().uuidString, wordFull: word.trimmingCharacters(in: .whitespacesAndNewlines), hint: hint.trimmingCharacters(in: .whitespacesAndNewlines), category: category, difficulty: difficulty, status: .pending)
                        if await state.submit(card) { dismiss() }
                        busy = false
                    }
                }.disabled(busy || !WordEngine.validWord(word) || !(5...160).contains(hint.trimmingCharacters(in: .whitespacesAndNewlines).count))
                Text("Les propositions restent privées jusqu’à leur approbation. En mode local, elles ne sont pas transmises à un modérateur.").font(.footnote)
            }
        }.navigationTitle("Proposer une carte").navigationBarTitleDisplayMode(.inline)
    }
}
struct SubmissionsView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        List {
            if state.progress.submissions.isEmpty { ContentUnavailableView("À toi d’inventer", systemImage: "plus.rectangle", description: Text("Tes propositions et leur statut apparaîtront ici.")) }
            ForEach(state.progress.submissions) { submission in
                VStack(alignment: .leading, spacing: 8) {
                    Text(submission.card.wordFull).font(.headline)
                    Text(submission.card.wordNoVowels).font(.subheadline.monospaced()).foregroundStyle(CNSNNTheme.accent)
                    Label(status(submission.card.status), systemImage: submission.card.status == .approved ? "checkmark.circle" : "clock").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
        }.navigationTitle("Mes propositions").task { await state.refreshSubmissions() }
    }
    private func status(_ value: ReviewStatus) -> String {
        switch value { case .pending: "En attente"; case .approved: "Approuvée"; case .rejected: "Refusée" }
    }
}
