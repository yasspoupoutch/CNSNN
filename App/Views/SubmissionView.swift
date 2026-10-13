import SwiftUI
import CNSNNCore

/// "Proposer un mot" tab: card proposal form and the player's submissions.
struct ProposeView: View {
    @Environment(AppState.self) private var state
    @State private var word = ""
    @State private var hint = ""
    @State private var category = CNSNNCore.Category.general
    @State private var difficulty = Difficulty.easy
    @State private var busy = false
    @State private var sent = false
    @FocusState private var focus: Field?
    private enum Field { case word, hint }
    private var trimmedHint: String { hint.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !busy && WordEngine.validWord(word) && (5...160).contains(trimmedHint.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Proposer un mot").scaledFont(34, .bold).tracking(-0.6)
                    .padding(.horizontal, 2).padding(.top, 6).accessibilityAddTraits(.isHeader)
                Text("Les mots validés par l’équipe rejoignent le jeu.")
                    .scaledFont(15).foregroundStyle(Palette.secondary).padding(.horizontal, 2).padding(.bottom, 4)
                preview
                field("Votre mot", text: $word, field: .word)
                    .scaledFont(18, .semibold).tracking(1)
                ZStack(alignment: .topTrailing) {
                    field("Votre indice", text: $hint, field: .hint, multiline: true)
                        .scaledFont(16)
                    Text("\(trimmedHint.count)/160").scaledFont(13).monospacedDigit()
                        .foregroundStyle((5...160).contains(trimmedHint.count) || trimmedHint.isEmpty ? Palette.tertiary : Palette.red)
                        .padding(.top, 18).padding(.trailing, 16).accessibilityHidden(true)
                }
                chips(CNSNNCore.Category.allCases, selection: $category)
                chips(Difficulty.allCases, selection: $difficulty)
                Button(busy ? "Envoi…" : (state.uid == nil ? "Enregistrer la proposition" : "Envoyer pour validation"), action: send)
                    .buttonStyle(PrimaryPillStyle(height: 54)).disabled(!canSend).padding(.top, 2)
                Text(sent ? (state.uid == nil ? "✓ Proposition enregistrée sur cet iPhone." : "✓ Proposition envoyée. Vous verrez son statut ci-dessous.") : (state.uid == nil ? "Y compte comme une voyelle. Sans serveur, les propositions restent sur cet iPhone." : "Y compte comme une voyelle. Chaque mot n’existe qu’une fois dans le jeu. Jusqu’à 10 propositions par jour, privées jusqu’à leur validation."))
                    .scaledFont(12).foregroundStyle(sent ? Palette.mint : Palette.tertiary).padding(.horizontal, 4)
                Text("Mes propositions").scaledFont(15, .semibold).padding(.horizontal, 2).padding(.top, 12)
                submissions
            }.padding(.horizontal, 20).padding(.top, 8)
        }
        .tabBarInset().scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        .task { await state.refreshSubmissions() }
    }

    private var preview: some View {
        VStack(spacing: 0) {
            SectionKicker(text: "Aperçu en jeu").frame(maxWidth: .infinity, alignment: .leading)
            let consonants = WordEngine.consonants(word)
            FlowLayout(spacing: 6) {
                ForEach(Array((consonants.isEmpty ? "···" : consonants).enumerated()), id: \.offset) { _, letter in
                    Text(String(letter)).scaledFont(24, .bold)
                        .foregroundStyle(consonants.isEmpty ? Palette.tertiary : Palette.foreground)
                        .frame(width: 42, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fill1))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
                }
            }
            .frame(minHeight: 52).padding(.top, 16).padding(.bottom, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(consonants.isEmpty ? "Les consonnes apparaîtront ici" : "Consonnes : " + consonants.map(String.init).joined(separator: ", "))
            Text(trimmedHint.isEmpty ? "Votre indice apparaîtra ici" : "« \(trimmedHint) »")
                .font(Typo.serifItalic(19)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(minHeight: 24)
        }.glassCard(radius: 30, padding: 20)
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field, multiline: Bool = false) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Palette.tertiary), axis: multiline ? .vertical : .horizontal)
            .lineLimit(multiline ? 1...4 : 1...1)
            .foregroundStyle(Palette.foreground)
            .autocorrectionDisabled(field == .word)
            .textInputAutocapitalization(field == .word ? .characters : .sentences)
            .focused($focus, equals: field)
            .padding(.leading, 18).padding(.trailing, field == .hint ? 70 : 18).padding(.vertical, 16)
            .frame(minHeight: 54)
            .glassPanel(radius: 18, padding: 0)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(focus == field ? Palette.focusRing : .clear, lineWidth: 1))
            .accessibilityLabel(field == .word ? "Mot complet" : "Indice, 5 à 160 caractères")
    }

    private func chips<Item: RawRepresentable & Hashable & Identifiable>(_ items: [Item], selection: Binding<Item>) -> some View where Item.RawValue == String {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                Chip(title: item.rawValue, selected: selection.wrappedValue == item) { selection.wrappedValue = item }
            }
        }.frame(maxWidth: .infinity)
    }

    @ViewBuilder private var submissions: some View {
        if state.progress.submissions.isEmpty {
            Text("Vos propositions et leur statut apparaîtront ici.").scaledFont(14).foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading).glassPanel(radius: 24, padding: 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(state.progress.submissions.reversed().enumerated()), id: \.element.id) { index, submission in
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(submission.card.wordFull.uppercased()).scaledFont(16, .bold).tracking(0.8)
                            Text(submission.card.wordNoVowels + " · " + submission.card.hint).scaledFont(13).foregroundStyle(Palette.tertiary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        status(submission.card.status)
                    }.padding(.horizontal, 16).padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }
            }.glassPanel(radius: 24, padding: 0)
        }
    }

    private func status(_ value: ReviewStatus) -> some View {
        let (label, color, fill): (String, Color, Color) = switch value {
        case .pending: ("En attente", Palette.secondary, Palette.fill2)
        case .approved: ("Validé", Palette.mint, Palette.mint.opacity(0.16))
        case .rejected: ("Refusé", Palette.red, Palette.redSoft)
        }
        return Text(label).scaledFont(12, .semibold).foregroundStyle(color)
            .padding(.horizontal, 10).frame(minHeight: 26).background(Capsule().fill(fill))
    }

    private func send() {
        guard canSend else { return }
        busy = true; sent = false; focus = nil
        Task {
            let card = Card(id: UUID().uuidString, wordFull: word.trimmingCharacters(in: .whitespacesAndNewlines), hint: trimmedHint, category: category, difficulty: difficulty, status: .pending)
            if await state.submit(card) {
                Haptics.success()
                word = ""; hint = ""; sent = true
            }
            busy = false
        }
    }
}
