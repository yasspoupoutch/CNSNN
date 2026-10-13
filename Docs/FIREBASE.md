# Connexion au projet Firebase existant

Le fichier iOS fourni a été inspecté et intégré : projet `cnsnn-9ctosy`, bundle `com.mycompany.cnsnn`. Aucune identité administrateur Firebase n’est disponible dans cet environnement. Aucune ressource distante n’a été inspectée ou modifiée. La base `(default)` sera conservée ; les fichiers de règles proposés doivent être comparés aux règles existantes avant déploiement.

## Configuration iOS reçue

`App/Resources/GoogleService-Info.plist` est une ressource de la cible CNSNN. Le projet Xcode et son générateur conservent le bundle existant. La présence du fichier ne confirme pas l’activation des fournisseurs Auth ni les règles Firestore déployées.

Les fournisseurs **Anonyme** et **Email/mot de passe** sont activés, d’après la confirmation de l’utilisateur du 6 octobre 2026. L’authentification effective depuis l’app reste à tester sur iOS.

Les captures fournies le 6 octobre 2026 montrent la base `(default)` sans collection visible et les règles par défaut refusant toutes les lectures/écritures. Le texte visible a été retranscrit dans `Firebase/baseline/firestore-observed-2026-10-06.rules` ; ce constat provient des captures, pas d’une lecture API. Cette sauvegarde ne fait pas partie de la configuration de déploiement.

L’utilisateur confirme la publication des règles CNSNN le 6 octobre 2026. Cette publication a été effectuée par l’utilisateur dans la console ; elle n’a pas été relue par API ni testée via l’émulateur dans cet environnement.

Prochaine étape : créer l’index composite `cards` : `createdBy` croissant, `createdAt` décroissant, portée Collection. Cet index est nécessaire à la consultation des propositions les plus récentes. Sa définition est déjà enregistrée dans `Firebase/firestore.indexes.json`. Le projet Firebase est rattaché dans `.firebaserc`, sans exécution de déploiement.

## Référence : obtenir le fichier iOS

1. Sur le PC Windows, ouvrir https://console.firebase.google.com/ et sélectionner **le projet CNSNN existant**.
2. Cliquer sur la roue dentée à côté de « Vue d’ensemble du projet », puis **Paramètres du projet**.
3. Dans **Général → Vos applications**, choisir l’application iOS si elle existe, puis **Télécharger GoogleService-Info.plist**.
4. Joindre ce fichier dans la conversation.

Si aucune application iOS n’est enregistrée, cliquer sur l’icône **iOS** dans « Vos applications », saisir `com.mycompany.cnsnn` comme identifiant de bundle et `CNSNN` comme nom. L’ID App Store peut rester vide. Cliquer sur **Enregistrer l’application**, puis télécharger le fichier. Ne créez pas un second projet Firebase et n’activez pas de plan facturable.

Si l’application iOS existante utilise un autre identifiant de bundle, fournir le fichier existant : l’identifiant du projet Xcode sera adapté après inspection. Ne supprimez pas l’application existante.

L’assistant pourra ensuite rattacher ce fichier aux ressources Xcode. `Scripts/connect_firebase.py` automatise cette opération lorsque l’identifiant correspond. Il ne fait aucune écriture réseau et refuse d’écraser un fichier différent.

## Étapes suivantes, à traiter séparément avec l’assistant

Après inspection de cette configuration : vérifier les fournisseurs Auth existants, activer l’anonyme si nécessaire, puis email/mot de passe pour la conversion ; lire les règles et index actuels avant de proposer leur mise à jour ; lancer les tests émulateur ; déployer uniquement les changements validés. Le code ne suppose pas que ces services ont déjà été activés.

## Coût

Auth anonyme et Firestore peuvent être utilisés dans les quotas Spark gratuits. Les quotas réels de votre projet et les conditions actuelles Firebase doivent être vérifiés avant publication. Aucun Firebase Storage, numéro de téléphone, analytics, tâche planifiée ou Function n’est activé par ce dépôt.

Cloud Functions exige généralement le plan Blaze. `Backend/functions/` est du code préparatoire **non déployé**, absent de la configuration de déploiement. Il faut prévenir l’utilisateur et obtenir son accord avant toute activation de facturation. Les limites d’instances réduisent le risque sans constituer un plafond financier. Un budget Firebase n’est pas un interrupteur automatique des dépenses.

## Publier les règles et nommer un administrateur

Une seule fois : dans la console Firebase, **Paramètres du projet → Comptes de service → Générer une nouvelle clé privée**, puis sur GitHub **Settings → Secrets and variables → Actions → New repository secret** nommé `FIREBASE_SERVICE_ACCOUNT` avec tout le contenu du fichier JSON. Ne jamais publier cette clé ailleurs.

Ensuite, depuis **Actions → CNSNN - Firebase → Run workflow** sur `main` :
- `deploy` coché : relance les tests émulateur puis publie `firestore.rules` et `firestore.indexes.json` sur `cnsnn-9ctosy` ;
- `admin_uid` : donne le rôle de modérateur à cet UID (claim `admin` et document `admins/{uid}`).

Sans la clé, un document `admins/{uid}` créé à la main dans la console suffit aussi pour la modération.

## Schéma (plan gratuit Spark, sans Cloud Functions)

| Collection | Contenu | Écriture |
|---|---|---|
| users/{uid} | pseudo, dates, quota de propositions | création à zéro, pseudo et quota par le propriétaire ; suppression par le propriétaire |
| users/{uid}/private/progress | progression d’entraînement synchronisée (JSON) | propriétaire uniquement |
| users/{uid}/friends/{amiUid} | amis ajoutés par code (pseudo, date) | propriétaire uniquement |
| friendCodes/{CODE} | code ami de 6 caractères → uid, pseudo | création par le propriétaire ; lecture d’un code par tout joueur, liste de ses seuls codes |
| dailySessions/{uid_day} | carte du jour, début serveur, indice, fin serveur | création une fois le jour même ; indice puis fin une seule fois |
| dailyResults/{uid_day} | résultat officiel public : temps = fin − début serveur, points recalculés | création unique, avec la mise à jour du classement dans le même lot |
| leaderboard/{uid} | points, parties, victoires, séries, meilleur temps | n’avance que d’un nouveau résultat à la fois |
| dailyPuzzles/{day} | mot du jour secret : consonnes, catégorie, difficulté | outil `tools/daily.mjs` (Admin SDK) ; lecture le jour même et les jours passés |
| dailyHints/{day} | indice du mot secret | lecture après l’avoir révélé (indice noté dans la session) ou la partie finie |
| dailySecrets/{day} | réponse normalisée, mot, indice | lecture une fois sa partie finie, ou le jour passé ; une victoire doit porter cette réponse |
| dailyChallenges/{day} | mot du jour publié par un modérateur (remplace le planning intégré) | modérateur, difficulté du jour imposée |
| cards/{MOTNORMALISÉ} | proposition ou carte publiée (avec le pseudo de l’auteur) ; l’identifiant empêche les doublons | proposition pending avec quota (30 s, 10/24 h) ; modération |
| reports/{uid_card} | signalement unique par joueur et carte | création propriétaire, résolution modérateur |
| admins/{uid} | rôle modérateur | console ou workflow uniquement |

Index composites : `cards` (createdBy, createdAt desc), `dailyResults` (day, correct, timeMs) et (userId, day desc).

## Mot du jour secret

La liste des mots du jour n’est dans le dépôt que chiffrée (`Firebase/daily/words.enc.json`, AES-256-GCM avec une clé chiffrée par la clé publique du compte de service). Seul le secret `FIREBASE_SERVICE_ACCOUNT` peut la déchiffrer.

- Publier ou prolonger les jours : workflow **CNSNN - Firebase** sur `main`, case `daily_seed`. Le jour même et les jours passés ne sont jamais réécrits.
- Changer la liste : `node tools/daily.mjs encrypt mots.tsv` (une ligne par mot : `F|M|D`, catégorie, mot, indice, séparés par des tabulations), puis committer seulement le fichier chiffré. La clé publique est dans `Firebase/daily/public.pem` (workflow, case `daily_public_key`, pour la régénérer).
- L’app envoie chaque proposition comme fin de partie avec la réponse normalisée : les règles refusent une mauvaise réponse, donc personne ne peut annoncer une victoire sans connaître le mot. Le mot n’est révélé qu’après la fin de sa propre partie.
- Sans mot secret publié pour un jour, l’app revient à l’ancienne liste intégrée (publique).

## Sécurité et limites

Les règles ont des tests émulateur inclus mais n’ont pas été exécutées dans l’environnement initial, faute d’installation des dépendances. Ne pas les considérer comme validées pour production avant ces tests. Les règles n’effectuent pas de normalisation linguistique : les propositions sont privées, et le modérateur recalcule les consonnes/réponses lors de l’approbation. Limiter le spam en production nécessitera App Check et quotas fiables côté serveur ; les bornes de champs ne constituent pas une limitation de fréquence.

Les mots des défis classés doivent être éditoriaux et ne pas être copiés dans le catalogue Classique public. Sinon, leur réponse est déjà téléchargeable. L’indice reste privé dans `dailySolutions` et ne se révèle que par la fonction qui applique la pénalité.

Le backend classé doit être testé en transactions concurrentes : reprise, doublons, midnight, indice, abandon, réseau interrompu et App Check. Les six tests de domaine exécutés ne remplacent pas cette validation. L’interface actuelle reste en mode quotidien local même quand Auth/Firestore sont configurés.
