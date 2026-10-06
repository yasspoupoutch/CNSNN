# CNSNN — iPhone / SwiftUI

Projet natif iOS créé dans ce dépôt. SwiftUI reste la seule technologie d’interface. Aucun service Firebase existant n’a été modifié et aucun service payant n’a été activé.

## Ouvrir l’application

Sur un **Mac avec Xcode 26 ou plus récent**, ouvrir `CNSNN.xcodeproj`, puis sélectionner le schéma **CNSNN**. Le projet cible iPhone, portrait, iOS 17 minimum. Xcode résoudra les dépendances Firebase par Swift Package Manager. Sans `GoogleService-Info.plist`, l’application utilise automatiquement son mode local.

Le SDK iOS 26 est requis pour compiler les références aux APIs Liquid Glass, même lorsque l’app sera installée sur iOS 17. Sur iOS 26, les contrôles utilisent `glassEffect`, `GlassEffectContainer` et la barre d’onglets système. Sur iOS 17–25, ils utilisent des matériaux système. Les transitions de navigation contextuelles utilisent les APIs iOS 18 lorsque disponibles.

**Aucune build iOS n’a été compilée dans l’environnement de création Linux.** Les tailles d’écran, animations, contrastes et performances doivent être vérifiés sur simulateur puis sur iPhone avant de considérer le design comme final.

## Ce qui est implémenté dans les sources

- Présentation courte et pseudo, sans formulaire email obligatoire.
- Home / Stats / Profil et navigation native conservant les pages.
- Classique : 30 cartes françaises, six catégories, trois difficultés, indice, validation, abandon, score, sélection évitant les répétitions récentes.
- Mot du jour local identique pour un même calendrier éditorial : date Europe/Paris, carte verrouillée au démarrage, résultat unique sauvegardé, reprise conservant le début du chronomètre.
- Statistiques locales, série quotidienne, graphique sobre et progression par paliers.
- Sauvegarde locale atomique protégée, conservée entre les lancements.
- Pseudo modifiable, formulaire de proposition, aperçu des consonnes, historique des propositions.
- Adaptateurs Firebase : compte anonyme, conversion email/mot de passe par `link`, connexion, déconnexion, catalogue approuvé, propositions privées, signalements, modération par custom claim administrateur.
- Règles Firestore et index. Les scores officiels sont exclusivement écrits par serveur.
- Backend optionnel pour un Mot du jour classé : sessions serveur, réponses privées, temps serveur, validation, attribution transactionnelle et idempotente. Il n’est ni déployé, ni branché à l’interface actuelle.
- Icône originale, manifeste de confidentialité initial, tests XCTest, test UI et tests de règles Firebase.

## Limites précises de cette livraison

Ce dépôt constitue une première implémentation, pas une version certifiée prête pour l’App Store.

La configuration iOS du projet existant `cnsnn-9ctosy` est rattachée aux ressources Xcode, avec le bundle `com.mycompany.cnsnn`. La connexion effective à Auth et Firestore reste à vérifier sur iOS. Le catalogue et le Mot du jour actuels fonctionnent localement ; les scores affichés sont des **points d’entraînement locaux**, pas un classement sécurisé. La progression n’est pas synchronisée entre appareils. La conversion anonyme conserve l’UID et la progression locale sur le même iPhone ; les propositions Firestore restent attachées au même UID. Une connexion à un autre compte ne fusionne pas les historiques locaux. La déconnexion conserve une archive locale par UID, restaurée lors d’une reconnexion sur le même appareil. Voir `Docs/ARCHITECTURE.md`.

Le classement communautaire, les percentiles, la synchronisation de progression, la suppression complète du compte, Sign in with Apple et le cycle TestFlight ne sont pas livrés comme fonctions opérationnelles. Le backend classé requiert intégration, tests émulateur et une décision préalable sur le coût. Aucun faux percentile n’est affiché.

## Vérifications

Exécutées ici : vérifications structurelles des sources/configurations/projet Xcode ; six tests de logique JavaScript du backend optionnel. Ce résultat ne vérifie pas l’implémentation Swift équivalente.

Non exécutées ici : compilation Swift, XCTest, tests UI, tests des règles Firestore, tests d’intégration Firebase et profiling iOS. Aucun compilateur Swift/Xcode n’est installé ; l’accès au proxy réseau a échoué lors de l’installation des outils.

Commandes prévues sur les environnements adéquats :

```sh
python3 Scripts/verify_project.py
node --test --test-isolation=none Backend/functions/tests/domain.test.mjs
swift test
cd Firebase
npm install
npm test
```

Pour tester l’app avec Xcode : **Product → Test**. Le test UI utilise `--uitesting`, isole ses données en mémoire et n’initialise jamais Firebase.

## Prochaine étape utilisateur

Les fournisseurs **Anonyme** et **Email/mot de passe** sont activés et les règles CNSNN sont publiées, selon les confirmations utilisateur du 6 octobre 2026. Prochaine étape : créer l’index composite du catalogue de propositions (`cards`, `createdBy` croissant, `createdAt` décroissant, portée Collection). La connexion réelle depuis l’app reste à vérifier avec Xcode.

Les guides de reprise sont dans `Docs/`. Le code est organisé en `Core/`, `App/`, `Firebase/`, `Backend/` et `Tests/`.
