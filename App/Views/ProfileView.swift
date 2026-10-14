import SwiftUI
import CNSNNCore

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var editingName = false
    @State private var name = ""
    @State private var account = false
    @State private var moderation = false
    @State private var privacy = false
    @State private var rules = false
    /// Signature at the bottom of the profile.
    private var credits: some View {
        VStack(spacing: 6) {
            HighlightedWord(word: "CONSONNE", font: Typo.wordmark(20))
            Text("Une application créée par Poupoutch").scaledFont(13, .medium).foregroundStyle(Palette.secondary)
            Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")).scaledFont(12).foregroundStyle(Palette.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profil").scaledFont(34, .bold).tracking(-0.6)
                    .padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    AvatarView(name: state.progress.username, colorIndex: avatar, size: 96)
                        .shadow(color: Palette.glassShadow, radius: 20, y: 16)
                    Text(state.progress.username).scaledFont(28, .bold).tracking(-0.5).padding(.top, 16)
                    Text("Niveau \(state.progress.score / 1000 + 1) · \(Format.number(state.progress.score)) points")
                        .scaledFont(15).foregroundStyle(Palette.secondary).padding(.top, 4)
                    AvatarPicker(selection: $avatar).padding(.top, 18)
                    Button("Modifier le pseudo") { name = state.progress.username; editingName = true }
                        .buttonStyle(GlassPillStyle(height: 48)).padding(.top, 18)
                }.frame(maxWidth: .infinity).glassCard(radius: 34, padding: 22)
                VStack(spacing: 0) {
                    Button { account = true } label: { row(state.isAnonymous ? "Sauvegarder mon compte" : "Mon compte", symbol: "person.crop.circle.badge.checkmark") }
                    if state.isAdmin {
                        Rectangle().fill(Palette.line).frame(height: 1)
                        Button { moderation = true } label: { row("Modération", symbol: "checkmark.shield") }
                    }
                }.glassPanel(radius: 24, padding: 0).buttonStyle(PressStyle(scale: 0.99))
                if state.isSuspended {
                    Text(AppState.suspendedText).scaledFont(14).foregroundStyle(Palette.red).glassPanel(radius: 24, padding: 18)
                }
                ReminderSettings()
                VStack(spacing: 0) {
                    Link(destination: Support.mail) { row("Contacter le support", symbol: "envelope") }
                    Rectangle().fill(Palette.line).frame(height: 1)
                    Button { privacy = true } label: { row("Confidentialité", symbol: "hand.raised") }
                    Rectangle().fill(Palette.line).frame(height: 1)
                    Button { rules = true } label: { row("Règles de la communauté", symbol: "person.2") }
                }.glassPanel(radius: 24, padding: 0).buttonStyle(PressStyle(scale: 0.99))
                Text(state.uid == nil ? "Mode local : votre progression reste sur cet iPhone." : (state.isAnonymous ? "Compte invité sauvegardé en ligne. Créez un compte pour le retrouver sur un autre iPhone." : "Compte permanent : votre progression vous suit sur tous vos appareils."))
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.horizontal, 4)
                credits.padding(.top, 18)
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
            .sheet(isPresented: $account) { AccountView() }
            .sheet(isPresented: $moderation) { NavigationStack { ModerationView() } }
            .sheet(isPresented: $privacy) { PrivacyView() }
            .sheet(isPresented: $rules) { CommunityRulesView() }
            .alert("Modifier le pseudo", isPresented: $editingName) {
                TextField("Pseudo", text: $name)
                Button("Enregistrer") { Task { await state.rename(name) } }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Entre 2 et 20 caractères.") }
            .task {
                state.isAdmin = (try? await state.cloud?.isAdmin()) ?? state.isAdmin
                if let uid = state.uid { state.isSuspended = (try? await state.cloud?.isSuspended(uid: uid)) ?? state.isSuspended }
            }
    }
    private func row(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.secondary).frame(width: 24)
            Text(title).scaledFont(16, .semibold).foregroundStyle(Palette.foreground)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }.padding(.horizontal, 18).frame(minHeight: 58).contentShape(Rectangle())
    }
}
/// Daily Mot du jour reminder: a local notification at the chosen time, nothing sent by a server.
struct ReminderSettings: View {
    @Environment(AppState.self) private var state
    @State private var enabled = Reminders.isEnabled
    @State private var time = ReminderSettings.date(minutes: Reminders.minutes)
    @State private var refused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $enabled) {
                HStack(spacing: 14) {
                    Image(systemName: "bell.badge").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.secondary).frame(width: 24)
                    Text("Rappel du mot du jour").scaledFont(16, .semibold).foregroundStyle(Palette.foreground)
                }
            }
            .tint(Palette.mint).padding(.horizontal, 18).frame(minHeight: 58)
            if enabled {
                Rectangle().fill(Palette.line).frame(height: 1)
                DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
                    .scaledFont(15).foregroundStyle(Palette.secondary).padding(.horizontal, 18).frame(minHeight: 52)
            }
            if refused {
                Text("Les notifications sont désactivées pour CNSNN. Autorisez-les dans Réglages > Notifications.")
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.horizontal, 18).padding(.bottom, 14)
            }
        }
        .glassPanel(radius: 24, padding: 0)
        .onChange(of: enabled) { _, on in
            Task {
                if on {
                    let allowed = await Reminders.enable()
                    refused = !allowed
                    if !allowed { enabled = false }
                } else {
                    Reminders.disable()
                }
                state.refreshGlance(force: true)
            }
        }
        .onChange(of: time) { _, value in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
            Reminders.minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            state.refreshGlance(force: true)
        }
    }
    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}

struct AccountView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var login = false
    @State private var confirmDelete = false
    @State private var deletePassword = ""
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                if state.cloud == nil {
                    Section { Text("Le serveur n’est pas configuré. Votre progression reste enregistrée sur cet iPhone.") }
                } else if state.uid == nil {
                    Section { Text("Le serveur est injoignable pour le moment. Réessayez une fois connecté à Internet.") }
                } else if state.isAnonymous {
                    Section {
                        Picker("Compte", selection: $login) {
                            Text("Créer un compte").tag(false)
                            Text("J’ai déjà un compte").tag(true)
                        }.pickerStyle(.segmented)
                        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField(login ? "Mot de passe" : "Mot de passe (8 caractères minimum)", text: $password).textContentType(login ? .password : .newPassword)
                        Button(login ? "Se connecter" : "Créer mon compte") { authenticate() }
                            .disabled(busy || state.isBusy || trimmedEmail.isEmpty || (login ? password.isEmpty : password.count < 8))
                        if login {
                            Button("Mot de passe oublié ?") { resetPassword() }.disabled(busy || trimmedEmail.isEmpty)
                        }
                    } footer: {
                        Text(login
                             ? "Vos parties d’entraînement de cet iPhone rejoignent ce compte. Les Mots du jour joués en invité restent sur le profil invité."
                             : "Votre compte invité devient permanent : même profil, mêmes points, mêmes propositions. Vous pourrez le retrouver sur un autre iPhone ou après une réinstallation.")
                    }
                } else {
                    Section {
                        Label(state.email ?? "Compte permanent", systemImage: "checkmark.icloud")
                        Text("Votre progression est sauvegardée en ligne et suit votre compte sur tous vos appareils.").font(.footnote).foregroundStyle(.secondary)
                        Button("Se déconnecter") {
                            do { try state.signOut(); dismiss() }
                            catch { message = CloudError.message(error) }
                        }
                    }
                }
                if let message { Section { Text(message) } }
                if state.uid != nil {
                    Section {
                        Button(state.isAnonymous ? "Supprimer mes données" : "Supprimer mon compte", role: .destructive) { confirmDelete = true }.disabled(busy)
                    } footer: {
                        Text("Supprime votre profil, vos résultats, votre place au classement, vos amis, vos signalements et vos propositions non publiées. Les cartes déjà publiées restent dans le jeu, sans votre nom. Cette action est définitive.")
                    }
                }
            }
            .navigationTitle("Votre compte")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
            .overlay { if busy { ProgressView().controlSize(.large) } }
            .alert(state.isAnonymous ? "Supprimer vos données ?" : "Supprimer votre compte ?", isPresented: $confirmDelete) {
                if !state.isAnonymous { SecureField("Mot de passe", text: $deletePassword) }
                Button("Supprimer", role: .destructive) { deleteAccount() }
                Button("Annuler", role: .cancel) { deletePassword = "" }
            } message: {
                Text(state.isAnonymous ? "Toutes vos parties et propositions seront effacées." : "Saisissez votre mot de passe pour confirmer. Toutes vos données seront effacées.")
            }
        }
    }
    private func resetPassword() {
        run {
            try await state.cloud?.resetPassword(email: trimmedEmail)
            message = "Si cette adresse correspond à un compte, vous recevrez un lien pour choisir un nouveau mot de passe."
        }
    }
    private func authenticate() {
        run {
            do {
                if login { try await state.signIn(email: trimmedEmail, password: password) }
                else { try await state.createAccount(email: trimmedEmail, password: password) }
                Haptics.success()
                dismiss()
            } catch where CloudError.code(error) == .emailInUse {
                // The address already has an account: offer to sign in to it instead.
                login = true
                throw error
            }
        }
    }
    private func deleteAccount() {
        let password = state.isAnonymous ? nil : deletePassword
        deletePassword = ""
        run {
            try await state.deleteAccount(password: password)
            dismiss()
        }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil
        Task {
            defer { busy = false }
            do { try await work() } catch { message = CloudError.message(error) }
        }
    }
}

/// Where players reach the person running CNSNN.
enum Support {
    static let email = "jeucnsnn@gmail.com"
    static let mail = URL(string: "mailto:" + email + "?subject=CNSNN")!
}

/// What CNSNN stores and why, readable without leaving the app.
struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String)] = [
        ("Ce que nous enregistrons", "Votre pseudo, vos parties (mots du jour, temps, points, séries), vos propositions de cartes, vos signalements et vos amis ajoutés par code. Si vous créez un compte, votre adresse email sert uniquement à vous connecter."),
        ("Ce qui est public", "Votre pseudo et vos résultats officiels apparaissent dans les classements. Les cartes que vous proposez ne montrent pas votre nom aux autres joueurs. Votre email n’est jamais affiché."),
        ("Où sont les données", "Sur les serveurs Firebase de Google (Authentication et Cloud Firestore), et sur votre iPhone. Aucune publicité, aucun traceur, aucune revente de données."),
        ("Rapports de plantage", "Si l’application plante, un rapport technique anonyme (modèle d’appareil, version, endroit du code) est envoyé à Firebase Crashlytics pour corriger le problème. Il ne contient ni votre pseudo ni votre email."),
        ("Notifications et widget", "Le rappel du mot du jour et le widget sont calculés sur votre iPhone : rien n’est envoyé par un serveur."),
        ("Supprimer vos données", "Profil > Mon compte > Supprimer mon compte efface votre profil, vos résultats, votre place au classement, vos amis, vos signalements et vos propositions non publiées. Les cartes déjà publiées restent dans le jeu, sans votre nom."),
        ("Nous contacter", "Pour toute question ou demande sur vos données : " + Support.email + "."),
    ]
    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.0).font(.headline)
                        Text(section.1).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                Link("Politique de confidentialité complète", destination: Site.privacy)
            }
            .navigationTitle("Confidentialité")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}
