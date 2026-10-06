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

## Schéma

| Collection | Contenu | Écriture |
|---|---|---|
| users/{uid} | pseudo, dates, score/stats officiels | création à zéro et pseudo par propriétaire ; statistiques par serveur |
| cards/{id} | mot, consonnes, réponse normalisée, indice, catégorie, difficulté, auteur, statut | proposition pending par auteur ; validation/retrait par claim admin |
| attempts/{uid_day} | résultat officiel quotidien, points, temps | serveur uniquement |
| dailyChallenges/{yyyy-MM-dd} | carte publique quotidienne sans réponse | outil éditorial de confiance |
| dailySolutions/{yyyy-MM-dd} | réponse et indice privés | outil éditorial de confiance ; aucune lecture client |
| gameSessions/{uid_day} | début serveur, indice révélé, statut | fonctions serveur uniquement |
| dailyResults/{uid_day} | résultat unique | serveur uniquement ; lecture propriétaire/admin |
| reports/{uid_card} | motif et statut | création propriétaire, résolution admin |

La région Functions proposée est europe-west1 ; vérifier la localisation Firestore réelle avant déploiement. Le fichier iOS ne donne pas les règles actuellement publiées : cette inspection nécessite un accès autorisé au projet.

## Sécurité et limites

Les règles ont des tests émulateur inclus mais n’ont pas été exécutées dans l’environnement initial, faute d’installation des dépendances. Ne pas les considérer comme validées pour production avant ces tests. Les règles n’effectuent pas de normalisation linguistique : les propositions sont privées, et le modérateur recalcule les consonnes/réponses lors de l’approbation. Limiter le spam en production nécessitera App Check et quotas fiables côté serveur ; les bornes de champs ne constituent pas une limitation de fréquence.

Les mots des défis classés doivent être éditoriaux et ne pas être copiés dans le catalogue Classique public. Sinon, leur réponse est déjà téléchargeable. L’indice reste privé dans `dailySolutions` et ne se révèle que par la fonction qui applique la pénalité.

Le backend classé doit être testé en transactions concurrentes : reprise, doublons, midnight, indice, abandon, réseau interrompu et App Check. Les six tests de domaine exécutés ne remplacent pas cette validation. L’interface actuelle reste en mode quotidien local même quand Auth/Firestore sont configurés.
