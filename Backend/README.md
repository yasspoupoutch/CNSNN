# Backend classé optionnel — non déployé

Les fonctions de `functions/` préparent un quotidien officiellement classé avec un début horodaté serveur, une solution privée, la pénalité d’indice, un résultat unique par UID/jour et un crédit de points atomique.

Elles ne sont pas référencées par `Firebase/firebase.json` et aucune commande de déploiement n’a été exécutée. Firebase Functions demande généralement le plan facturable Blaze : prévenir l’utilisateur et obtenir son accord avant toute mise en service. Le mode local et Auth/Firestore n’exigent pas ces fonctions.

Avant intégration : confirmer la région et le projet, ajouter App Check à l’app, créer des défis éditoriaux et solutions privés, tester les émulateurs et les transactions concurrentes, intégrer Firebase Functions dans l’interface, gérer l’offline et vérifier la suppression de compte. Le classement communautaire et les percentiles ne sont pas implémentés.

`beginDaily` renvoie un puzzle sans réponse. `revealDailyHint` met à jour la pénalité et renvoie l’indice privé. `answerDaily` ignore tout score/temps fourni par le client, utilise le temps serveur et retourne le résultat existant en cas de répétition. Une mauvaise réponse garde la session ouverte ; un abandon l’achève à zéro point. Les appels exigent Auth et App Check.

Les six tests de domaine sont exécutables sans dépendances Firebase :

```sh
node --test --test-isolation=none functions/tests/domain.test.mjs
```

Leur succès ne prouve pas l’intégration Firebase : le code de transactions n’a pas été exécuté dans cet environnement.
