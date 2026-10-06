# État des vérifications — 6 octobre 2026

## Réellement exécuté

- `python3 Scripts/verify_project.py` : validation structurelle du projet Xcode, XML, plist, JSON, ressources référencées, équilibre lexical basique des Swift et absence de règle globale ouverte. Ce contrôle n’est pas un compilateur.
- `node --test --test-isolation=none Backend/functions/tests/domain.test.mjs` : **6 tests passés**, logique du serveur optionnel.
- `node --check Backend/functions/index.mjs` : syntaxe JavaScript correcte ; import des SDK et exécution Firebase non vérifiés.

## Non exécuté

- Swift/XCTest : compilateur absent ; téléchargement bloqué par proxy inaccessible.
- Build et tests UI iOS : Xcode/macOS absents.
- Tests de sécurité Firestore : packages non installés ; accès réseau indisponible.
- Tests Functions/Firestore intégrés : émulateurs et dépendances non installés.
- Mesures de fluidité, VoiceOver et design sur appareil : aucun simulateur iOS disponible.

## Tests inclus

Swift : normalisation française, ligatures, consonnes, réponse vide/incorrecte, invariants du catalogue, score/indice/temps, calendrier parisien, changement d’heure, choix anti-répétition, persistance Codable et streak. La cible AppTests vérifie également sauvegarde atomique, isolation des comptes, corruption non écrasée, résultat quotidien unique et restauration de session.

UI : onboarding et navigation Home → Stats → Profil → Home en mode mémoire isolé.

Firestore : droits propriétaires, champs sensibles, admin non falsifiable, soumission pending privée, refus de l’auto-approbation, requête approved, refus d’énumération globale, refus des résultats forgés, signalement unique et résolution admin.

Backend : normalisation, points, jours Paris/DST, mauvais essais sans points, temps serveur et abandon.

## Matrice iPhone à exécuter sur Mac

- Petit iPhone/SE, format 393 × 852 et grand iPhone ; plus grandes tailles Dynamic Type.
- Clavier ouvert, scroll, Safe Area/Home Indicator, retour navigation en cours de partie.
- iOS 17 : fallback matériaux ; iOS 26 : verre natif, transitions, contraste en luminosité faible/forte.
- VoiceOver : pseudo, consonnes épelées, champ réponse, boutons, sélection onglets, graphe.
- Reduce Motion et Reduce Transparency.
- Mode avion, relance, fermeture pendant quotidien, changement de date, indices, abandon et double soumission.
- Compte anonyme → permanent : même UID, pseudo, documents ; tentative de collision email explicitement gérée par erreur, pas de suppression de l’invité.
- Firebase non configuré puis configuré, Auth refusé, Firestore refusé, lecture catalogue vide.
- Profil admin et non admin, carte refusée/approuvée, signalement déjà existant.
- Profiling Release avec Instruments : Animation Hitches, Time Profiler, consommation réseau et mémoire sur session longue. Aucune garantie de 60/120 fps sans ces mesures.

## Configuration Firebase — mise à jour

Le fichier iOS du projet `cnsnn-9ctosy` est intégré ; le bundle Debug/Release correspond à `com.mycompany.cnsnn`. Le 6 octobre 2026, l’utilisateur confirme l’activation des fournisseurs Anonyme et Email/mot de passe. Cette confirmation n’est pas un test de connexion. Le code comporte désormais la récupération de mot de passe ; elle n’a pas été exécutée contre Firebase. La lecture des règles distantes est encore en attente.

L’utilisateur confirme ensuite la publication des règles CNSNN. Cela confirme une opération dans la console, sans remplacer les tests des permissions par émulateur. L’index composite des propositions reste à créer. Aucun déploiement distant n’a été exécuté par l’assistant.
