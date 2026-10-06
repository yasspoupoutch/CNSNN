# Architecture et décisions

## Cœur de jeu

`Core/` est une bibliothèque Swift sans Firebase, SwiftUI ou UIKit. Elle peut être testée via Swift Package Manager sur un système disposant de Swift. Le projet Xcode compile la même bibliothèque dans une cible statique : aucune deuxième copie du moteur.

`WordEngine` normalise la casse française, supprime les diacritiques, développe les ligatures Œ/Æ et conserve les seules lettres ASCII. Les espaces, tirets et apostrophes n’affectent pas la réponse. Y est une voyelle dans cette édition. Les pluriels et variantes synonymiques ne sont pas automatiquement acceptés. Les cartes sont françaises ; une extension à d’autres langues devra préciser cette convention.

Le score local vaut 50/100/150 selon la difficulté, plus un bonus décroissant de 50 à 0 sur 50 secondes, puis division entière par deux si indice. Une erreur n’achève pas la carte. Un abandon termine la carte à zéro point. Le taux de réussite mesure les cartes résolues, pas les frappes soumises.

`DailySchedule` utilise le calendrier grégorien en Europe/Paris. Le hash déterministe opère sur un catalogue local trié ; le catalogue quotidien local reste figé aux cartes initiales, indépendamment des cartes Firebase. Une future édition du catalogue devra migrer vers des défis publiés serveur pour conserver la continuité entre versions.

## Application

`AppState`, observable et MainActor, contient le profil local et les dépendances. `GameSession` isole la logique de la partie. Les vues ne déclenchent aucune requête dans `body`. Les lectures cloud sont bornées : catalogue 100, propositions 100, modération 50 par liste. Ajouter pagination avant un catalogue public volumineux. Pas de listeners permanents ni d’analytics publicitaires.

`LocalRepository` écrit un fichier Codable atomiquement, avec protection iOS. Un fichier illisible bloque les nouvelles écritures pour éviter de remplacer silencieusement les données. Le schéma devra recevoir une migration explicite avant modification d’une version publiée. Les essais et propositions sont actuellement conservés dans le fichier ; prévoir un stockage paginé lorsque l’historique devient volumineux.

Le Classique utilise ContinuousClock, suspendu en arrière-plan. Le quotidien local utilise un instant de début persisté, incluant l’arrière-plan et une reprise après fermeture, afin de ne pas réinitialiser le temps. L’utilisateur peut modifier l’horloge ou ses fichiers : ce mécanisme local n’a aucune valeur pour un classement officiel.

La conversion anonyme par Firebase `link(with:)` garde l’UID, donc les documents et propositions associés. Les données locales restent sur le même appareil. La connexion à un compte existant est une opération différente : pas de fusion automatique. La déconnexion remet l’interface en état d’onboarding tout en conservant un fichier séparé par UID. La reconnexion au même compte sur cet appareil restaure cette archive. La synchronisation entre appareils reste requise avant une sortie publique promettant une sauvegarde cloud. Aucun score local ne doit être importé comme score officiel.

## Design natif

Fond noir, surfaces anthracite, accent sauge clair, typographie système arrondie pour les titres et monospace pour les consonnes. Le verre est limité aux capsules, actions et navigation. Le contenu repose sur des surfaces opaques lisibles.

`TabView` bénéficie du rendu natif du système installé, y compris Liquid Glass sur iOS 26 ; aucune fausse barre flottante n’est reconstruite. `GlassEffectContainer` regroupe les capsules. Les transitions zoom contextuelles utilisent les APIs iOS 18. Les pressions se compriment de 2 % maximum. Reduce Motion supprime compression et zoom ; Reduce Transparency remplace les capsules translucides par des surfaces opaques. Les listes, scrolls, composants adaptatifs et safe areas prennent en charge le clavier et les tailles d’iPhone. Ces intentions doivent être confirmées dans Xcode avec les grandes tailles de texte.

## Firebase et frontières de confiance

Auth constitue la source pour l’UID, l’email et le statut anonyme. Ces champs ne sont pas utilisés comme droits client modifiables. Firestore contient le pseudo et des statistiques officielles protégées. Le serveur peut faire évoluer ces statistiques ; le client peut uniquement renommer son profil.

Un admin possède un custom claim **signé par Firebase Auth** `admin: true`, attribué depuis un environnement Admin SDK de confiance. Le masquage de la page admin améliore l’UX ; les règles restent la véritable protection.

Les réponses des cartes Classique approuvées sont accessibles pour le jeu d’entraînement local. Elles ne doivent pas servir de secrets pour un classement. Le backend quotidien optionnel utilise une collection privée `dailySolutions`, des sessions privées et des défis publics sans réponses. Toutes ces collections privées sont bloquées par le refus par défaut des règles.

Les fonctions classées sont volontairement absentes de `Firebase/firebase.json`. Une intégration future devra ajouter l’adaptateur Firebase Functions à l’app, App Check, gestion du réseau, restauration serveur et tests transactionnels. Le package serveur actuel prépare ce chemin sans engager la facturation.

Sign in with Apple pourra utiliser une nouvelle credential Firebase et le même chemin `link`, avec nonce cryptographique et gestion de collision des comptes. Aucune UI Apple non fonctionnelle n’est affichée.
