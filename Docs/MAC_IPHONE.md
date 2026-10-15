# Reprise sur Mac et iPhone

Le développement des sources peut continuer depuis Windows. Pour produire CNSNN.app, les SDK Apple, Xcode et macOS sont indispensables. Aucune archive .app ni signature n’est fournie dans cette livraison.

## Première étape sur Mac

Ouvrir `CNSNN.xcodeproj` avec **Xcode 26 ou plus récent**. Le schéma partagé CNSNN est inclus et les packages Firebase sont référencés. Attendre la résolution des dépendances. Signaler à l’assistant le premier message d’erreur éventuel : il pourra corriger les sources, une étape à la fois.

## Validation, à effectuer ensuite

Lancer sur un simulateur iPhone, puis Product → Test. Les tests Core sont aussi exécutables avec `swift test` indépendamment de Firebase. La suite UI repart de zéro en mémoire.

Pour l’installation physique : sélectionner la cible CNSNN, Signing & Capabilities, une Team Apple personnelle ou développeur et un identifiant de bundle disponible. Le bundle proposé est `com.poupoutch.cnsnn`. Si l’identifiant change, l’enregistrement Firebase doit correspondre. Brancher l’iPhone, le choisir comme destination, activer Developer Mode quand iOS le demande, puis Run. Un compte personnel permet certains essais sur appareil avec des limites Apple ; TestFlight/App Store requiert le programme développeur adapté.

Ces opérations ne doivent pas toutes être demandées en une fois à l’utilisateur : l’assistant guidera uniquement l’étape actuellement bloquante.

## Passage TestFlight / App Store

Avant toute distribution : compilation Release et Analyze sans warnings pertinents ; tests sur appareil ; vérification de la synchronisation/conversion de compte ; récupération de compte et suppression complète des données ; politique de confidentialité publique ; formulaire App Privacy conforme au comportement final et aux manifests Firebase ; App Check pour le backend classé ; absence de secret serveur dans le bundle ; paramètres de signature et App Store Connect réels ; review du contenu communautaire et de ses outils de signalement.

Le manifeste de confidentialité fourni couvre l’UID, le pseudo, l’email optionnel et le contenu proposé. Il doit être revérifié contre les versions effectives des SDK et leurs APIs à raisons obligatoires. La publication n’est pas automatisée ni engagée.
