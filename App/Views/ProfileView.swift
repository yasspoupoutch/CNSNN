import SwiftUI
import CNSNNCore

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @AppStorage(CNSNNTheme.avatarKey) private var avatar = 0
    @State private var editingName = false
    @State private var name = ""
    @State private var account = false
    @State private var moderation = false
    @State private var isAdmin = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Profil").font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .padding(.horizontal, 2).padding(.top, 6).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    AvatarView(name: state.progress.username, colorIndex: avatar, size: 96)
                        .shadow(color: Palette.glassShadow, radius: 20, y: 16)
                    Text(state.progress.username).font(.system(size: 28, weight: .bold)).tracking(-0.5).padding(.top, 16)
                    Text("Niveau \(state.progress.score / 1000 + 1) · \(Format.number(state.progress.score)) points locaux")
                        .font(.system(size: 15)).foregroundStyle(Palette.secondary).padding(.top, 4)
                    AvatarPicker(selection: $avatar).padding(.top, 18)
                    Button("Modifier le pseudo") { name = state.progress.username; editingName = true }
                        .buttonStyle(GlassPillStyle(height: 48)).padding(.top, 18)
                }.frame(maxWidth: .infinity).glassCard(radius: 34, padding: 22)
                VStack(spacing: 0) {
                    Button { account = true } label: { row(state.isAnonymous ? "Sauvegarder mon compte" : "Mon compte", symbol: "person.crop.circle.badge.checkmark") }
                    if isAdmin {
                        Rectangle().fill(Palette.line).frame(height: 1)
                        Button { moderation = true } label: { row("Modération", symbol: "checkmark.shield") }
                    }
                }.glassPanel(radius: 24, padding: 0).buttonStyle(PressStyle(scale: 0.99))
                Text(state.cloud == nil ? "Mode local. Votre compte Firebase sera disponible après la connexion du projet." : "La conversion du compte invité conserve le même identifiant Firebase et les propositions associées.")
                    .font(.footnote).foregroundStyle(Palette.tertiary).padding(.horizontal, 4)
            }.padding(.horizontal, 20).padding(.top, 8)
        }.tabBarInset().scrollIndicators(.hidden)
            .sheet(isPresented: $account) { AccountView() }
            .sheet(isPresented: $moderation) { NavigationStack { ModerationView() } }
            .alert("Modifier le pseudo", isPresented: $editingName) {
                TextField("Pseudo", text: $name)
                Button("Enregistrer") { Task { await state.rename(name) } }
                Button("Annuler", role: .cancel) {}
            } message: { Text("Entre 2 et 20 caractères.") }
            .task { isAdmin = (try? await state.cloud?.isAdmin()) ?? false }
    }
    private func row(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 24)
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.foreground)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }.padding(.horizontal, 18).frame(height: 58).contentShape(Rectangle())
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
