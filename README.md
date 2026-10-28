# CNSNN

**Disponible sur l'App Store** : [télécharger CNSNN sur iPhone](https://apps.apple.com/app/id6823569042) (version 1.2). La version Android arrive bientôt sur Google Play.

Jeu de mots en SwiftUI (iPhone) et Kotlin (Android) : retrouver un mot à partir de ses seules consonnes. Firebase gère les comptes, la synchronisation et les classements. L'app reste entièrement sur l'offre gratuite Spark : pas de Cloud Functions, aucun service payant.

## Fonctionnalités

- **Mot du jour commun et secret** : le même mot pour tout le monde. L'app ne reçoit que les consonnes, le serveur vérifie chaque réponse et ne révèle le mot qu'à la fin de la partie. La difficulté suit le jour : facile le lundi et le mardi, moyen du mercredi au vendredi, difficile le week-end. Le chrono part et s'arrête sur l'horloge du serveur. Le score est le temps (+1 min avec l'indice, 10 min si raté), recalculé par les règles Firestore, une partie par jour, et une partie interrompue reprend avec son chrono d'origine. Chaque essai est compté par le serveur avant d'être vérifié : 20 essais par jour, un par seconde.
- **Résultat** : « Vous êtes le numéro 1 ! », ou Top 1 %, 5 %, 10 %, 25 % ou 50 % du jour, avec le rang (« 3e sur 120 aujourd'hui »).
- **Classements** : aujourd'hui (temps), mois (somme des temps du mois, un jour raté ou pas joué compte 10 min), records, et **amis** (ajout par code de 6 caractères, classés sur le mot du jour).
- **Classique** : 421 cartes intégrées et les cartes de la communauté approuvées, six catégories et trois difficultés, sans répéter les cartes récentes.
- **Sprint** : 90 secondes, un mot après l'autre. Points selon la difficulté × combo (×1 à ×5) ; une erreur ou un mot passé remet le combo à ×1, passer coûte 5 secondes. Le chrono ne s'arrête jamais (verrouiller le téléphone ne fait pas gagner de temps) ; un Sprint interrompu par la fermeture de l'app est compté tel quel.
- **Survie** : 3 vies. Une erreur ou un mot passé coûte une vie ; une vie regagnée tous les 10 mots (3 au plus). Un niveau tous les 5 mots, avec de plus en plus de mots difficiles. Partie sauvegardée après chaque mot : on la reprend plus tard ou on l'abandonne.
- **Double sens** : 5 manches de deux mots aux mêmes consonnes (FRN : FARINE et FREIN), chacun avec son indice. Score selon les réponses, les erreurs et le temps. 61 duos.
- **Records personnels** des trois modes dans Stats, synchronisés avec le compte (fusion par appareil : aucune partie perdue ni comptée deux fois). Ils n'entrent dans aucun classement.
- **Comptes** : invité automatique, puis compte e-mail sans perte de données. Connexion, mot de passe oublié, suppression du compte et de toutes ses données. Progression synchronisée entre appareils et conservée après réinstallation.
- **Propositions de cartes** : doublons impossibles (l'identifiant est le mot normalisé), 30 s entre deux propositions, 10 par 24 h, statuts en attente, approuvée ou refusée, signalements.
- **Fréquentation** (administrateurs, Profil → Fréquentation) : par jour, téléphones qui ont ouvert l’app ou joué, nouveaux appareils, parties par mode. Des totaux anonymes (`stats/{jour}`), sans nom ni identifiant ; environ une écriture par téléphone et par jour.
- **Modération** (administrateurs) : approuver ou refuser une carte, corriger son indice, sa catégorie ou sa difficulté, voir son auteur, traiter les signalements.
- **Tutoriel de démarrage** : au premier lancement, l'accueil s'assombrit autour du mot du jour (bouton Jouer qui pulse), puis montre un exemple fixe (TR : TROU… ou AUTEUR…), jamais le vrai mot du jour, puis « Si vous ne trouvez pas… prenez un indice ! » (le bouton Indice clignote, le toucher révèle l’indice et AUTEUR), avec le thème et le chrono. 5 étapes. « Revoir le tutoriel » dans Profil.
- **Rappel quotidien** : notification locale à l'heure choisie dans Profil, plus un rappel le soir si la série est en jeu.
- **Widget** écran d'accueil (petit et moyen) : mot du jour à jouer, trouvé ou raté, série et temps avant le prochain mot.
- **Design** Liquid Glass : effets natifs sur iOS 26, matériaux système sur iOS 17 à 25. Retours haptiques, Dynamic Type, cibles de 44 pt. Les réglages « Réduire les animations » et « Réduire la transparence » sont respectés.

## Installer

- **iPhone** : [CNSNN sur l'App Store](https://apps.apple.com/app/id6823569042), gratuit, iOS 17 ou plus récent.
- **Android** : bientôt sur Google Play (application dans `Android/`).

Les versions de test passent par TestFlight (workflow **CNSNN - iPhone TestFlight**). Le workflow **CNSNN - IPA iPhone non signe** reste disponible pour installer une version de développement avec [Sideloadly](https://sideloadly.io).

## Firebase

- Projet `cnsnn-9ctosy`, bundle `com.poupoutch.cnsnn`, connexions Anonyme et E-mail/mot de passe.
- La sécurité repose sur `Firebase/firestore.rules`. Pour publier les règles, lancer le workflow **CNSNN - Firebase** sur `main` avec `deploy` coché. Il utilise le secret `FIREBASE_SERVICE_ACCOUNT` et `Firebase/tools/deploy.mjs`.
- Index composites : voir `Firebase/firestore.indexes.json`. La clé du compte de service ne peut pas les créer : ils se créent dans la console Firebase.
- Nommer un administrateur : même workflow, champ `admin_uid` rempli avec l'UID du joueur.
- Détails, schéma des collections et limites : `Docs/FIREBASE.md`.

**Mots du jour secrets** : la liste (364 mots, `Firebase/daily/words*.enc.json`) n'est dans ce dépôt que chiffrée, et seul le compte de service Firebase peut la lire. Personne ne peut annoncer une victoire sans le bon mot, ni un temps plus court que celui du serveur, ni rejouer, ni truquer son total du mois. Détails dans `Docs/FIREBASE.md`.

## Site public

https://cnsnn-9ctosy.web.app : présentation (sans APK : le plan gratuit refuse les fichiers exécutables), [règles de la communauté](https://cnsnn-9ctosy.web.app/regles), [politique de confidentialité](https://cnsnn-9ctosy.web.app/confidentialite) et [suppression de compte](https://cnsnn-9ctosy.web.app/suppression). Sources dans `Firebase/hosting`, publiées par le workflow **CNSNN - Firebase** (case `site`). Publication sur l'App Store et Google Play : `Docs/PUBLICATION.md`.

## Développer et tester

- Ouvrir `CNSNN.xcodeproj` avec Xcode 26 ou plus récent (SDK iOS 26), schéma **CNSNN**. iOS 17 minimum, iPhone, portrait.
- Le projet est généré par `python3 Scripts/generate_project.py`, puis vérifié par `python3 Scripts/verify_project.py`.
- **Tests des règles** (Node 22 et Java 21) : `cd Firebase && npm install && npm test`. Ils couvrent les profils, la synchro, le mot du jour, le classement, les amis, les cartes, la modération et la suppression.
- **Contenu** : `python3 Scripts/generate_content.py` vérifie `Shared/cards.tsv` et `Shared/duos.tsv` (orthographe normalisée, doublons, indices sans la réponse, mêmes consonnes pour un duo), écrit les fichiers des deux plateformes et des scénarios de jeu rejoués par les tests Swift et Kotlin. Le workflow Firebase vérifie qu'aucune carte ni aucun duo n'est un mot du jour secret.
- **Tests iOS** : workflow **CNSNN - iOS Simulator**. Il compile l'app et lance les tests unitaires, les tests de bout en bout contre les émulateurs Firebase avec les vraies règles (`Tests/Integration`) et, en option, les tests d'interface.

## Organisation

| Dossier | Contenu |
|---|---|
| `Core/` | moteur du jeu, cartes, planning du mot du jour, modèles, règles des modes (bibliothèque partagée avec le widget) |
| `Shared/` | cartes et duos Double sens ajoutés (TSV) : `python3 Scripts/generate_content.py` les vérifie et écrit le code Swift et Kotlin |
| `App/` | application SwiftUI : vues, état, accès Firebase, design system |
| `Widget/` | widget WidgetKit |
| `Firebase/` | règles, index, tests des règles, outils de publication |
| `Tests/` | tests unitaires, d'intégration Firebase et d'interface |
| `Docs/` | architecture, Firebase, Mac/iPhone, recette |
| `Backend/` | fonctions serveur optionnelles (offre Blaze payante), non déployées |
