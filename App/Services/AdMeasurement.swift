import Foundation
import FirebaseCore
import FirebaseAnalytics

/// Lets Google Ads count the installs that come from CNSNN's ads, only if the player said yes.
/// Minimal on purpose: FirebaseAnalyticsCore (no advertising identifier, no AdSupport, no ATT prompt),
/// IDFV and ad personalisation off in Info.plist, collection off until the answer, and no custom event:
/// only Firebase's automatic ones (first_open, sessions). Installs are then matched by Google with
/// GoogleAdsOnDeviceConversion (matching done on the iPhone, no identifier leaves it; without it an
/// iPhone install can't be linked to the ad click and Google Ads shows 0), Apple's SKAdNetwork and its estimates.
enum AdMeasurement {
    /// No value: never asked. true / false: the player's answer (changeable in Profil).
    static let key = "cnsnn.adMeasurement"
    static var answer: Bool? { UserDefaults.standard.object(forKey: key) as? Bool }
    static var isOn: Bool { answer == true }
    /// Only new players are asked, once, on the first screen; others can turn it on in Profil.
    static var shouldAsk: Bool {
        answer == nil && (!RuntimeFlags.isTesting || ProcessInfo.processInfo.arguments.contains("--ask-ads"))
    }
    static let question = "CNSNN fait un peu de publicité. Pour savoir si elle amène de nouveaux joueurs, l’app peut envoyer à Google des statistiques anonymes d’utilisation : ni pseudo, ni email, ni identifiant publicitaire. Vous pourrez changer d’avis dans Profil."
    static func set(_ on: Bool) {
        let wasOn = isOn
        UserDefaults.standard.set(on, forKey: key)
        apply()
        // Turning it off also wipes what Analytics kept on this iPhone.
        if wasOn && !on && FirebaseApp.app() != nil { Analytics.resetAnalyticsData() }
    }
    /// At launch (after FirebaseApp.configure) and whenever the answer changes.
    static func apply() {
        guard FirebaseApp.app() != nil, !RuntimeFlags.isTesting else { return }
        let status: ConsentStatus = isOn ? .granted : .denied
        Analytics.setConsent([.analyticsStorage: status, .adStorage: status, .adUserData: status, .adPersonalization: .denied])
        Analytics.setAnalyticsCollectionEnabled(isOn)
    }
}
