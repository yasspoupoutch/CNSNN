# Publier CNSNN sur l'App Store et Google Play

Ce qui est prêt dans le dépôt, et ce qu'il restera à faire le jour où les comptes développeur seront payés (99 € par an chez Apple, 25 $ une fois chez Google).

Guide pas à pas et textes des fiches : dans les notes du projet (`notes/publication/`). Ordre conseillé : Google Play d'abord, à cause du test fermé de 14 jours, et l'iPhone en parallèle.

## Déjà en place

| Exigence des stores | Où |
|---|---|
| Politique de confidentialité publique (URL) | https://cnsnn-9ctosy.web.app/confidentialite (`Firebase/hosting/confidentialite.html`) |
| Suppression du compte dans l'app (Apple 5.1.1(v), Google) | Profil > Mon compte > Supprimer mon compte, iPhone et Android |
| Suppression du compte depuis le web (Google Play) | https://cnsnn-9ctosy.web.app/suppression (`Firebase/hosting/suppression.html`, même code que les apps, testé dans `Firebase/tests/account.test.mjs`) |
| Contenu créé par les joueurs (Apple 1.2) : règles acceptées, filtre, signalement, blocage, modération | Règles de la communauté acceptées à l'inscription (version dans `users/{uid}.rulesVersion`), filtre des pseudos, signalement des cartes et des pseudos, suspension réversible, temps suspects visibles en Modération |
| Contact support | jeucnsnn@gmail.com, dans l'app et sur le site |
| Manifeste de confidentialité iOS | `App/Resources/PrivacyInfo.xcprivacy` (identifiant, pseudo, email, contenu de jeu et des joueurs) |
| Chiffrement (export) | `ITSAppUsesNonExemptEncryption = false` dans `App/Resources/Info.plist` |
| Rapports de plantage | Firebase Crashlytics sur Android. Retiré sur iPhone : soupçonné de faire planter l'app dans les tests avec Xcode 27 (à réessayer avec une version plus récente du SDK) |

## À faire avant la première soumission iPhone

1. **Identifiant de l'app** : `com.poupoutch.cnsnn` (comme Android), App Group `group.com.poupoutch.cnsnn`, app Firebase « CNSNN iPhone ». L'ancienne app Firebase `com.mycompany.cnsnn` reste en place pour les versions déjà installées avec Sideloadly.
2. **Version** : `MARKETING_VERSION = 1.0` ; le numéro de build vient du numéro d'exécution du workflow TestFlight.
3. **Signature et envoi, sans Mac.** Le workflow **CNSNN - iPhone TestFlight** (`ios-testflight.yml`, lancé à la main) archive l'app, laisse Xcode créer le certificat de distribution et les profils (app et widget, avec l'App Group) grâce à une clé API App Store Connect, puis envoie le build sur App Store Connect. Secrets du dépôt à créer :
   - `APPLE_TEAM_ID` : l'identifiant d'équipe (Membership details sur developer.apple.com) ;
   - `ASC_KEY_ID` et `ASC_ISSUER_ID` : App Store Connect > Utilisateurs et accès > Intégrations > Clés de l'équipe, clé avec le rôle **Admin** (nécessaire pour créer le certificat) ;
   - `ASC_KEY_P8` : le contenu du fichier `.p8` téléchargé (une seule fois possible).
4. **App Store Connect :**
   - Catégorie : Jeux > Mots. Classification : 4+ (pas de contenu choquant ; contenu des joueurs modéré).
   - Confidentialité de l'app : Identifiants (ID utilisateur), Coordonnées (email), Contenu utilisateur (contenu de jeu, autre contenu), Diagnostics (données de plantage). Tout « lié à l'utilisateur » sauf les plantages, rien pour le suivi publicitaire.
   - URL de confidentialité et d'assistance : celles du site.
   - Compte de démonstration pour la revue : un compte email de test (la revue doit pouvoir jouer et voir la modération si on la mentionne).
   - Captures : iPhone 6,9 pouces et 6,5 pouces (accueil, partie, résultat, classement, amis). Les captures 6,9 pouces (1320 x 2868) se font avec le workflow **CNSNN - Captures App Store** : profil et classement inventés, hors ligne, publiés en artefact et sur la branche `store-screenshots` (`ios/light/` ou `ios/dark/`). Le workflow **CNSNN - Fiche App Store** envoie les textes de `Store/app-store-fr.json`, la catégorie et ces captures dans App Store Connect ; **CNSNN - Préparer la revue App Store** affiche puis (case `apply`) règle la build, la classification d'âge, le prix gratuit et la disponibilité. Aucun des deux ne soumet à la revue.
5. **Connexion avec Apple** : pas obligatoire, l'app ne propose aucune connexion tierce (Google, Facebook).
6. **Statut de commerçant (DSA)** : à déclarer dans App Store Connect pour être distribué dans l'Union européenne. App gratuite sans revenus : « pas commerçant », sinon l'adresse et le téléphone sont publiés.
7. **SDK** : Apple exige au moins Xcode 26 et le SDK iOS 26 ; la CI utilise Xcode 27.

## À faire avant la première soumission Android

1. **Niveau d'API cible.** `targetSdk = 36`, le niveau exigé pour les nouvelles apps depuis le 31 août 2026 (Google le relève chaque année).
2. **Clé de signature.** La clé actuelle (`Android/signing/release.enc.json`) peut devenir la clé d'importation de Play App Signing. Ne jamais la régénérer, sinon les APK déjà installés ne pourront plus se mettre à jour.
3. **Format.** Le Play Store demande un AAB : le workflow Android le produit (artefact **CNSNN-Android-AAB**). Le premier AAB s'envoie à la main dans la Play Console.
4. **Compte personnel récent** : test fermé obligatoire avec au moins 12 testeurs pendant 14 jours avant la production.
5. **Play Console :**
   - Sécurité des données : identifiant, email, contenu de jeu, contenu des joueurs, journaux de plantage. Collectés, non partagés, chiffrés en transit, suppression possible (lien web ci-dessus). Pas de publicité.
   - Suppression de compte : l'URL du site.
   - Classification du contenu (questionnaire IARC) : jeu de mots, contenu des joueurs modéré.
   - Public cible : 13 ans et plus (pas de programme Familles).
6. **Restreindre les clés Firebase** (gratuit) dans Google Cloud > Identifiants : la clé Android à `com.poupoutch.cnsnn` + empreinte SHA-1 de la clé de signature, la clé iOS à l'identifiant iOS définitif. La clé web reste limitée au domaine `cnsnn-9ctosy.web.app`.

## Quotas gratuits à surveiller (plan Spark)

- Firestore : 50 000 lectures et 20 000 écritures par jour. Les cartes sont gardées sur l'appareil (version `meta/cards`) et les classements limités à 25 lignes ; une partie classée coûte environ deux écritures par essai.
- Hosting : 10 Go de transfert par mois. Le plan gratuit refuse les fichiers exécutables : l'APK Android n'est pas sur le site, il passera par le Play Store.
