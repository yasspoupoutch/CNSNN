import SwiftUI
import CNSNNCore

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @State private var editingName = false
    @State private var name = ""
    @State private var account = false
    @State private var moderation = false
    @State private var isAdmin = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 72, weight: .light)).foregroundStyle(CNSNNTheme.accent).accessibilityHidden(true)
                    Text(state.progress.username).font(.title.weight(.semibold))
                    Text("Niveau \(state.progress.score / 1000 + 1) · \(state.progress.score) points locaux").foregroundStyle(.secondary)
                    Button("Modifier le pseudo") { name = state.progress.username; editingName = true }.buttonStyle(.bordered).controlSize(.large)
                }.frame(maxWidth: .infinity).cnsnnSurface()
                NavigationLink { SubmissionView() } label: { profileRow("Proposer une carte", symbol: "plus.rectangle") }
                NavigationLink { SubmissionsView() } label: { profileRow("Mes propositions", symbol: "tray") }
                Button { account = true } label: { profileRow(state.isAnonymous ? "Sauvegarder mon compte" : "Mon compte", symbol: "person.crop.circle.badge.checkmark") }
                if isAdmin { NavigationLink { ModerationView() } label: { profileRow("Modération", symbol: "checkmark.shield") } }
                Text(state.cloud == nil ? "Mode local. Ton compte Firebase sera disponible après la connexion du projet." : "La conversion du compte invité conserve le même identifiant Firebase et les propositions associées.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(CNSNNTheme.background).navigationTitle("Profil").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $account) { AccountView() }
            .alert("Modifier le pseudo", isPresented: $editingName) {
                TextField("Pseudo", text: $name)
                Button("Enregistrer") { Task { await state.rename(name) } }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Entre 2 et 20 caractères.") }
            .task { isAdmin = (try? await state.cloud?.isAdmin()) ?? false }
    }
    private func profileRow(_ title: String, symbol: String) -> some View {
        HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "chevron.right").font(.caption) }
            .font(.headline).padding(20).background(CNSNNTheme.surface, in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(.white)
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
    var body: some View {
        NavigationStack {
            Form {
                if state.cloud == nil {
                    Section { Text("Firebase n’est pas encore configuré. Ta progression reste enregistrée sur cet iPhone.") }
                } else if state.isAnonymous {
                    Section {
                        Text("Un compte conserve ton identifiant invité. Utilise une nouvelle adresse pour convertir ce compte.")
                        Toggle("J’ai déjà un compte", isOn: $login)
                        TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Mot de passe", text: $password).textContentType(login ? .password : .newPassword)
                        Button(login ? "Se connecter" : "Créer mon compte") { authenticate() }.disabled(busy || state.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (login ? password.isEmpty : password.count < 8))
                        if login {
                            Button("Mot de passe oublié ?") { resetPassword() }
                                .disabled(busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if login { Text("La connexion change de compte. La progression locale n’est pas fusionnée automatiquement.").font(.footnote) }
                    }
                } else {
                    Section {
                        Label("Compte permanent connecté", systemImage: "checkmark.shield")
                        Button("Se déconnecter", role: .destructive) {
                            do { try state.signOut(); dismiss() }
                            catch { message = error.localizedDescription }
                        }
                    }
                }
                if let message { Section { Text(message) } }
            }.navigationTitle("Ton compte").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        }
    }
    private func resetPassword() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let cloud = state.cloud else { return }
                try await cloud.resetPassword(email: email)
                message = "Si cette adresse correspond à un compte, tu recevras un lien pour choisir un nouveau mot de passe."
            } catch { message = error.localizedDescription }
        }
    }
    private func authenticate() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                guard let cloud = state.cloud else { return }
                let profile = try await cloud.authenticate(email: email, password: password, login: login)
                try state.activate(profile, preservingGuest: !login)
                await state.refreshCards()
                dismiss()
            } catch { message = error.localizedDescription }
        }
    }
}
