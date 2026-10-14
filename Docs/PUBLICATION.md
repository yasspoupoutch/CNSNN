# Publier CNSNN sur l'App Store et Google Play

Ce qui est prêt dans le dépôt, et ce qu'il restera à faire le jour où les comptes développeur seront payés (99 € par an chez Apple, 25 $ une fois chez Google).

## Déjà en place

| Exigence des stores | Où |
|---|---|
| Politique de confidentialité publique (URL) | https://cnsnn-9ctosy.web.app/confidentialite (`Firebase/hosting/confidentialite.html`) |
| Suppression du compte dans l'app (Apple 5.1.1(v), Google) | Profil > Mon compte > Supprimer mon compte, iPhone et Android |
| Suppression du compte depuis le web (Google Play) | https://cnsnn-9ctosy.web.app/suppression (`Firebase/hosting/suppression.html`, même code que les apps, testé dans `Firebase/tests/account.test.mjs`) |
| Contenu créé par les joueurs (Apple 1.2) : règles acceptées, filtre, signalement, blocage, modération | Règles de la communauté acceptées à l'inscription (version dans `users/{uid}.rulesVersion`), filtre des pseudos, signalement des cartes et des pseudos, suspension réversible, temps suspects visibles en Modération |
| Contact support | jeucnsnn@gmail.com, dans l'app et sur le site |
| Manifeste de confidentialité iOS | `App/Resources/PrivacyInfo.xcprivacy` (identifiant, pseudo, email, contenu de jeu et des joueurs, rapports de plantage) |
| Chiffrement (export) | `ITSAppUsesNonExemptEncryption = false` dans `App/Resources/Info.plist` |
| Rapports de plantage | Firebase Crashlytics, iPhone et Android |

## À faire avant la première soumission iPhone

1. **Identifiant de l'app.** Il vaut encore `com.mycompany.cnsnn` (et `group.com.mycompany.cnsnn` pour le widget). Choisir le définitif (par exemple `com.poupoutch.cnsnn`, comme Android), le changer dans `Scripts/generate_project.py`, `App/CNSNN.entitlements`, `Widget/CNSNNWidget.entitlements` et `Core/Glance.swift`, puis enregistrer une nouvelle app iOS dans la console Firebase et remplacer `App/Resources/GoogleService-Info.plist`. À faire seulement à ce moment-là : avec Sideloadly, un nouvel identifiant installe une autre app, et un compte invité resterait sur l'ancienne.
2. **Version.** `MARKETING_VERSION` passe de `0.1.0` à `1.0` dans `Scripts/generate_project.py`.
3. **Signature.** Compte Apple Developer, certificat de distribution et profils (app et widget, avec l'App Group). Le workflow `ios-unsigned-ipa.yml` deviendra un workflow d'archive signée vers TestFlight.
4. **App Store Connect :**
   - Catégorie : Jeux > Mots. Classification : 4+ (pas de contenu choquant ; contenu des joueurs modéré).
   - Confidentialité de l'app : Identifiants (ID utilisateur), Coordonnées (email), Contenu utilisateur (contenu de jeu, autre contenu), Diagnostics (données de plantage). Tout « lié à l'utilisateur » sauf les plantages, rien pour le suivi publicitaire.
   - URL de confidentialité et d'assistance : celles du site.
   - Compte de démonstration pour la revue : un compte email de test (la revue doit pouvoir jouer et voir la modération si on la mentionne).
   - Captures : iPhone 6,9 pouces et 6,5 pouces (accueil, partie, résultat, classement, amis).
5. **Connexion avec Apple** : pas obligatoire, l'app ne propose aucune connexion tierce (Google, Facebook).

## À faire avant la première soumission Android

1. **Niveau d'API cible.** `targetSdk = 35` dans `Android/app/build.gradle.kts` : Google Play exige chaque année un niveau plus récent pour les nouvelles apps (vérifier la règle en vigueur le jour de la soumission, probablement 36).
2. **Clé de signature.** La clé actuelle (`Android/signing/release.enc.json`) peut devenir la clé d'importation de Play App Signing. Ne jamais la régénérer, sinon les APK déjà installés ne pourront plus se mettre à jour.
3. **Format.** Le Play Store demande un AAB : ajouter `bundleRelease` au workflow Android.
4. **Compte personnel récent** : test fermé obligatoire avec au moins 12 testeurs pendant 14 jours avant la production.
5. **Play Console :**
   - Sécurité des données : identifiant, email, contenu de jeu, contenu des joueurs, journaux de plantage. Collectés, non partagés, chiffrés en transit, suppression possible (lien web ci-dessus). Pas de publicité.
   - Suppression de compte : l'URL du site.
   - Classification du contenu (questionnaire IARC) : jeu de mots, contenu des joueurs modéré.
   - Public cible : 13 ans et plus (pas de programme Familles).
6. **Restreindre les clés Firebase** (gratuit) dans Google Cloud > Identifiants : la clé Android à `com.poupoutch.cnsnn` + empreinte SHA-1 de la clé de signature, la clé iOS à l'identifiant iOS définitif. La clé web reste limitée au domaine `cnsnn-9ctosy.web.app`.

## Quotas gratuits à surveiller (plan Spark)

- Firestore : 50 000 lectures et 20 000 écritures par jour. Les cartes sont gardées sur l'appareil (version `meta/cards`) et les classements limités à 25 lignes ; une partie classée coûte environ deux écritures par essai.
- Hosting : 10 Go de transfert par mois. Chaque téléchargement de l'APK en consomme une part : passer au Play Store le moment venu.
