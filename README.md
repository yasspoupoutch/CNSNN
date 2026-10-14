# CNSNN

Jeu de mots iPhone en SwiftUI : retrouver un mot à partir de ses seules consonnes. Firebase gère les comptes, la synchronisation et les classements. L'app reste entièrement sur l'offre gratuite Spark : pas de Cloud Functions, aucun service payant.

## Fonctionnalités

- **Mot du jour commun et secret** : le même mot pour tout le monde. L'app ne reçoit que les consonnes, le serveur vérifie chaque réponse et ne révèle le mot qu'à la fin de la partie. La difficulté suit le jour : facile le lundi et le mardi, moyen du mercredi au vendredi, difficile le week-end. Le chrono part et s'arrête sur l'horloge du serveur. Les points sont recalculés par les règles Firestore, une partie par jour, et une partie interrompue reprend avec son chrono d'origine. Chaque essai est compté par le serveur avant d'être vérifié : 20 essais par jour, un par seconde.
- **Résultat** : « Vous êtes le numéro 1 ! », ou Top 1 %, 5 %, 10 %, 25 % ou 50 % du jour, avec le rang (« 3e sur 120 aujourd'hui »).
- **Classements** : aujourd'hui (temps), points, records, et **amis** (ajout par code de 6 caractères, classés sur le mot du jour).
- **Classique** : 134 cartes intégrées et les cartes de la communauté approuvées, six catégories et trois difficultés, sans répéter les cartes récentes.
- **Comptes** : invité automatique, puis compte e-mail sans perte de données. Connexion, mot de passe oublié, suppression du compte et de toutes ses données. Progression synchronisée entre appareils et conservée après réinstallation.
- **Propositions de cartes** : doublons impossibles (l'identifiant est le mot normalisé), 30 s entre deux propositions, 10 par 24 h, statuts en attente, approuvée ou refusée, signalements.
- **Modération** (administrateurs) : approuver ou refuser une carte, corriger son indice, sa catégorie ou sa difficulté, voir son auteur, traiter les signalements.
- **Rappel quotidien** : notification locale à l'heure choisie dans Profil, plus un rappel le soir si la série est en jeu.
- **Widget** écran d'accueil (petit et moyen) : mot du jour à jouer, trouvé ou raté, série et temps avant le prochain mot.
- **Design** Liquid Glass : effets natifs sur iOS 26, matériaux système sur iOS 17 à 25. Retours haptiques, Dynamic Type, cibles de 44 pt. Les réglages « Réduire les animations » et « Réduire la transparence » sont respectés.

## Installer sur iPhone (sans compte Apple payant)

1. Dans l'onglet **Actions** du dépôt, lancer **CNSNN - IPA iPhone non signe** sur `main`.
2. Télécharger l'artefact **CNSNN-iPhone-unsigned-IPA** (disponible 24 h) et le décompresser.
3. Installer `CNSNN-unsigned.ipa` avec [Sideloadly](https://sideloadly.io) et un identifiant Apple gratuit. Si Sideloadly refuse le partage de données du widget, installer `CNSNN-sans-widget-partage.ipa` à la place : le widget n'affichera alors que la difficulté du jour.
4. Avec un compte gratuit, l'app expire au bout de 7 jours. Il suffit de la réinstaller, rien n'est perdu.

TestFlight et l'App Store exigent le programme Apple Developer payant : ils ne sont pas utilisés.

## Firebase

- Projet `cnsnn-9ctosy`, bundle `com.mycompany.cnsnn`, connexions Anonyme et E-mail/mot de passe.
- La sécurité repose sur `Firebase/firestore.rules`. Pour publier les règles, lancer le workflow **CNSNN - Firebase** sur `main` avec `deploy` coché. Il utilise le secret `FIREBASE_SERVICE_ACCOUNT` et `Firebase/tools/deploy.mjs`.
- Index composites : voir `Firebase/firestore.indexes.json`. La clé du compte de service ne peut pas les créer : ils se créent dans la console Firebase.
- Nommer un administrateur : même workflow, champ `admin_uid` rempli avec l'UID du joueur.
- Détails, schéma des collections et limites : `Docs/FIREBASE.md`.

**Mots du jour secrets** : la liste (364 mots, `Firebase/daily/words*.enc.json`) n'est dans ce dépôt que chiffrée, et seul le compte de service Firebase peut la lire. Personne ne peut annoncer une victoire sans le bon mot, ni un temps plus court que celui du serveur, ni rejouer, ni gonfler ses points. Détails dans `Docs/FIREBASE.md`.

## Site public

https://cnsnn-9ctosy.web.app : présentation, téléchargement Android, [règles de la communauté](https://cnsnn-9ctosy.web.app/regles), [politique de confidentialité](https://cnsnn-9ctosy.web.app/confidentialite) et [suppression de compte](https://cnsnn-9ctosy.web.app/suppression). Sources dans `Firebase/hosting`, publiées par le workflow **CNSNN - Firebase** (case `site`). Ce qu'il reste pour l'App Store et Google Play : `Docs/PUBLICATION.md`.

## Développer et tester

- Ouvrir `CNSNN.xcodeproj` avec Xcode 26 ou plus récent (SDK iOS 26), schéma **CNSNN**. iOS 17 minimum, iPhone, portrait.
- Le projet est généré par `python3 Scripts/generate_project.py`, puis vérifié par `python3 Scripts/verify_project.py`.
- **Tests des règles** (Node 22 et Java 21) : `cd Firebase && npm install && npm test`. Ils couvrent les profils, la synchro, le mot du jour, le classement, les amis, les cartes, la modération et la suppression.
- **Tests iOS** : workflow **CNSNN - iOS Simulator**. Il compile l'app et lance les tests unitaires, les tests de bout en bout contre les émulateurs Firebase avec les vraies règles (`Tests/Integration`) et, en option, les tests d'interface.

## Organisation

| Dossier | Contenu |
|---|---|
| `Core/` | moteur du jeu, cartes, planning du mot du jour, modèles (bibliothèque partagée avec le widget) |
| `App/` | application SwiftUI : vues, état, accès Firebase, design system |
| `Widget/` | widget WidgetKit |
| `Firebase/` | règles, index, tests des règles, outils de publication |
| `Tests/` | tests unitaires, d'intégration Firebase et d'interface |
| `Docs/` | architecture, Firebase, Mac/iPhone, recette |
| `Backend/` | fonctions serveur optionnelles (offre Blaze payante), non déployées |
