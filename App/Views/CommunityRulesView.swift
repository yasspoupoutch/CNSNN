import SwiftUI

/// The community rules every player accepts (onboarding, or once when they change).
enum CommunityRules {
    /// Raise it when the rules change: every player is asked to accept them again.
    static let version = 1
    static let items: [(String, String)] = [
        ("Un pseudo correct", "Pas d’insulte, de propos haineux ou sexuels, ni d’usurpation d’identité."),
        ("Des cartes pour tous", "Les mots et indices proposés ne contiennent rien d’offensant ni de données personnelles."),
        ("Pas de triche", "Ni programme, ni aide automatique, ni comptes multiples pour fausser les classements."),
        ("Du respect", "Pas de harcèlement, pas de signalements abusifs."),
        ("La modération veille", "Elle peut refuser une carte, masquer un pseudo ou suspendre un compte. Une question : " + Support.email + "."),
    ]
}

/// Public pages of CNSNN (Firebase Hosting, free plan).
enum Site {
    static let home = URL(string: "https://cnsnn-9ctosy.web.app")!
    static let rules = URL(string: "https://cnsnn-9ctosy.web.app/regles")!
    static let privacy = URL(string: "https://cnsnn-9ctosy.web.app/confidentialite")!
}

/// The rules, readable from the profile, or to accept before playing on (`accepting`).
struct CommunityRulesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var accepting = false
    var body: some View {
        NavigationStack {
            List {
                if accepting {
                    Text("Pour que CNSNN reste agréable pour tous, merci de lire et d’accepter ces règles.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(CommunityRules.items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). \(item.0)").font(.headline)
                        Text(item.1).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Link("Lire la version complète", destination: Site.rules)
                if accepting {
                    Section {
                        Button("J’accepte") { Haptics.success(); state.acceptRules(); dismiss() }
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Règles de la communauté")
            .toolbar { if !accepting { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } } }
        }
        .interactiveDismissDisabled(accepting)
    }
}
