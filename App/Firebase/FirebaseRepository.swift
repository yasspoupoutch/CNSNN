import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import CNSNNCore
struct CloudProfile { let uid: String; let anonymous: Bool; let username: String }
struct CardReport: Identifiable { let id: String; let cardID: String; let reason: String }
@MainActor final class FirebaseRepository {
    static var isConfigured: Bool { FirebaseApp.app() != nil }
    static func configureIfPresent() {
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
    }
    private var auth: Auth { Auth.auth() }
    var hasCurrentUser: Bool { auth.currentUser != nil }
    private var db: Firestore { Firestore.firestore() }
    func bootstrap(username: String) async throws -> CloudProfile {
        let user: User
        if let current = auth.currentUser { user = current }
        else { user = try await auth.signInAnonymously().user }
        let ref = db.collection("users").document(user.uid)
        let doc = try await ref.getDocument(source: .server)
        if !doc.exists {
            try await ref.setData(["uid":user.uid,"username":username,"createdAt":FieldValue.serverTimestamp(),"updatedAt":FieldValue.serverTimestamp(),"score":0,"gamesPlayed":0,"correctAnswers":0,"bestTimeMs":NSNull(),"currentStreak":0])
        }
        return CloudProfile(uid:user.uid,anonymous:user.isAnonymous,username:doc.data()?["username"] as? String ?? username)
    }
    func rename(uid: String, username: String) async throws {
        try await db.collection("users").document(uid).updateData(["username":username,"updatedAt":FieldValue.serverTimestamp()])
    }
    func authenticate(email: String, password: String, login: Bool) async throws -> CloudProfile {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if login { _ = try await auth.signIn(withEmail:email,password:password) }
        else if let current = auth.currentUser, current.isAnonymous {
            // Linking preserves UID and ownership; never replace the anonymous user.
            _ = try await current.link(with:EmailAuthProvider.credential(withEmail:email,password:password))
        } else if auth.currentUser == nil {
            _ = try await auth.createUser(withEmail:email,password:password)
        } else { throw CloudError.permanentAccountAlreadyConnected }
        return try await bootstrap(username:"Joueur")
    }
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func signOut() throws { try auth.signOut() }
    func cards() async throws -> [Card] {
        let snap = try await db.collection("cards").whereField("status",isEqualTo:"approved").limit(to:100).getDocuments()
        return snap.documents.compactMap { decode($0.documentID,$0.data()) }
    }
    func submit(card: Card, uid: String) async throws {
        try await db.collection("cards").document(card.id).setData(["wordFull":card.wordFull,"wordNoVowels":card.wordNoVowels,"normalizedAnswer":WordEngine.normalize(card.wordFull),"hint":card.hint,"category":card.category.rawValue,"difficulty":card.difficulty.rawValue,"createdBy":uid,"createdAt":FieldValue.serverTimestamp(),"status":"pending"])
    }
    func submissions(uid: String) async throws -> [Submission] {
        let snap = try await db.collection("cards").whereField("createdBy",isEqualTo:uid).order(by:"createdAt",descending:true).limit(to:100).getDocuments()
        return snap.documents.compactMap { doc in
            guard let card = decode(doc.documentID,doc.data()) else { return nil }
            var s = Submission(card:card); s.id = doc.documentID
            s.createdAt = (doc.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            return s
        }
    }
    func report(cardID: String, reason: String) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("reports").document(uid+"_"+cardID).setData(["userId":uid,"cardId":cardID,"reason":reason,"createdAt":FieldValue.serverTimestamp(),"status":"pending"])
    }
    func isAdmin() async throws -> Bool {
        guard let user = auth.currentUser else { return false }
        return try await user.getIDTokenResult(forcingRefresh:true).claims["admin"] as? Bool == true
    }
    func pendingCards() async throws -> [Card] {
        let snap = try await db.collection("cards").whereField("status",isEqualTo:"pending").limit(to:50).getDocuments()
        return snap.documents.compactMap { decode($0.documentID,$0.data()) }
    }
    func review(card: Card, approved: Bool) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("cards").document(card.id).updateData(["status":approved ? "approved":"rejected","reviewedBy":uid,"reviewedAt":FieldValue.serverTimestamp(),"normalizedAnswer":WordEngine.normalize(card.wordFull),"wordNoVowels":WordEngine.consonants(card.wordFull)])
    }
    func pendingReports() async throws -> [CardReport] {
        let snap = try await db.collection("reports").whereField("status",isEqualTo:"pending").limit(to:50).getDocuments()
        return snap.documents.compactMap { doc in
            guard let cardID = doc.data()["cardId"] as? String, let reason = doc.data()["reason"] as? String else { return nil }
            return CardReport(id:doc.documentID,cardID:cardID,reason:reason)
        }
    }
    func withdraw(report: CardReport) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        let batch = db.batch()
        batch.updateData(["status": "rejected", "reviewedBy": uid, "reviewedAt": FieldValue.serverTimestamp()], forDocument: db.collection("cards").document(report.cardID))
        batch.updateData(["status": "resolved", "reviewedBy": uid, "reviewedAt": FieldValue.serverTimestamp()], forDocument: db.collection("reports").document(report.id))
        try await batch.commit()
    }
    func resolve(report: CardReport) async throws {
        guard let uid = auth.currentUser?.uid else { throw CloudError.authentication }
        try await db.collection("reports").document(report.id).updateData(["status":"resolved","reviewedBy":uid,"reviewedAt":FieldValue.serverTimestamp()])
    }
    private func decode(_ id: String, _ d: [String:Any]) -> Card? {
        guard let word = d["wordFull"] as? String, let hint = d["hint"] as? String,
        let category = Category(rawValue:d["category"] as? String ?? ""),
        let difficulty = Difficulty(rawValue:d["difficulty"] as? String ?? ""),
        let status = ReviewStatus(rawValue:d["status"] as? String ?? "") else { return nil }
        return Card(id:id,wordFull:word,hint:hint,category:category,difficulty:difficulty,status:status)
    }
}
enum CloudError: LocalizedError {
    case authentication
    case permanentAccountAlreadyConnected
    var errorDescription: String? {
        switch self {
        case .authentication: "Connecte-toi avant cette action."
        case .permanentAccountAlreadyConnected: "Un compte permanent est déjà connecté. Ferme cette fenêtre pour retrouver ton profil."
        }
    }
}
