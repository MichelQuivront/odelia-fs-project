# Mission : terminer intégralement le projet odelia-fs-project

Tu es un agent de développement qui tourne à la racine de ce dépôt : une application Kanban full-stack de cours, avec OpenLiberty, Jakarta EE 11, MicroProfile 7.1, Jakarta Data, PostgreSQL, Keycloak (MP-JWT) et Angular 20.
Ton objectif est de traiter **tous** les exercices de `exercises/` (01 à 17) :
- tu implémentes ce qui doit être codé ;
- tu rédiges des réponses argumentées pour les exercices d'analyse ;
- tu prouves que tout fonctionne avec des builds et des tests.

Tu travailles en autonomie. Arrête-toi pour me demander uniquement dans les cas listés plus bas, à la section « Quand t'arrêter ».

---

## 0. Règles absolues

1. **Lis avant d'écrire.** Avant toute modification, lis `README.md`, `backend/JAKARTA_MP_INTRO.md`, `frontend/ANGULAR_INTRO.md`, `keycloak/README.md`, tous les fichiers de `exercises/`, et l'ensemble de `backend/src` et `frontend/src`.
2. **Ne modifie jamais** `exercises/**` ni `exercises/solutions/**`. Ce sont des références en lecture seule.
3. **Respecte les conventions du projet :**
   - Jakarta Data : requêtes dérivées du nom de méthode, pas de JPQL écrit à la main.
   - Entités reliées par leur ID (`boardId`, `listId`), sans association JPA.
   - Contrôles d'autorisation centralisés dans `security/BoardAccess`, jamais dupliqués dans les ressources.
   - `ForbiddenException` pour les refus d'accès (403) et `WebApplicationException` 404 pour une ressource absente.
   - Suppressions en cascade gérées dans la couche ressource.
   - Frontend : composants standalone, signals, un signal `error` + `fail()`, et un `BoardService` qui ne manipule jamais de jeton.
4. **N'ajoute aucune dépendance** Maven ou npm sans me demander.
5. **Ne touche pas à la configuration de sécurité** (`server.xml`, `microprofile-config.properties`, `keycloak/kanban-realm.json`, `docker-compose.yml`), sauf si un exercice le demande explicitement (exercice 16). Documente alors chaque changement.
6. **Ne fabrique rien.** Si une information manque (mot de passe, comportement attendu), cherche-la dans le dépôt. Si elle n'y est pas, écris clairement « HYPOTHÈSE : … » dans `PROGRESS.md`.
7. **Un commit par exercice**, avec un message `exNN: <résumé>`, sur la branche `complete-project`. Si le dossier n'est pas un dépôt git, signale-le et continue sans commit.

## 1. Préparation de l'environnement

1. Identifie où tu tournes : Dev Container, hôte Linux/macOS ou Windows. Vérifie `java -version` (21 attendu), `mvn -v`, `node -v` (≥ 20.19 ou ≥ 22.12) et `docker compose version`.
2. Démarre l'infrastructure : `docker compose up -d postgres keycloak`. Attends que Keycloak réponde sur `http://localhost:8081/realms/kanban` (ou `http://keycloak:8080` depuis le Dev Container).
3. Lance le backend :
   - `cd backend && mvn liberty:dev` en arrière-plan, journaux redirigés vers `backend/liberty-dev.log` ;
   - ou bien `docker compose up -d --build backend`.
   Vérifie ensuite `GET http://localhost:9080/health/ready`, qui doit renvoyer 200.
4. **Piège connu : l'issuer JWT.** Les jetons doivent être demandés à `http://localhost:8081`, parce que l'issuer attendu est `mp.jwt.verify.issuer=http://localhost:8081/realms/kanban`. Un jeton obtenu via `keycloak:8080` est rejeté (401). Si le backend tourne hors Docker, exporte `MP_JWT_VERIFY_PUBLICKEY_LOCATION=http://localhost:8081/realms/kanban/protocol/openid-connect/certs`.
5. Écris dans `scripts/token.sh` un helper qui récupère un jeton par password grant (client `kanban-app`) pour alice, bob et carol. Prends les mots de passe dans `keycloak/README.md` ou `kanban-realm.json`.
6. Frontend : `cd frontend && npm ci` (ou `npm install`), puis `npx ng build`. Les scripts `npm test` utilisent la syntaxe bash `$(...)` : exécute-les dans un shell bash.

Si une étape échoue, diagnostique la cause (journaux, `docker compose logs`, ports déjà utilisés) et corrige-la avant de continuer. Note le problème et sa solution dans `PROGRESS.md`.

## 2. Inventaire initial (avant tout code)

Crée `PROGRESS.md` avec un tableau qui classe chaque exercice :

| # | Titre | Type (analyse / implémentation / test / sécurité) | Déjà fait dans le code ? (preuve : fichier + ligne) | Statut |

Points à vérifier explicitement :
- **Ex 09 (rename)** : `BoardService.renameBoard` existe. Vérifie si une interface de renommage existe aussi.
- **Ex 14 (endpoint current user)** : cherche un endpoint de type `/api/me`.
- **Ex 15 (tests ownership)** : `backend/src/test` existe-t-il ?
- **Ex 16 (mauvaise configuration)** : la faille est-elle encore présente ?
- **Ex 17 (BoardMember)** : est-il déjà partiellement ou totalement appliqué ? Un script `apply-exercise17.sh` a peut-être déjà été exécuté ; dans ce cas, ne recode pas : **vérifie et complète**.

Ensuite, présente-moi ce tableau et ton plan d'action. Attends mon « go » avant de modifier le code.

## 3. Traitement des exercices, dans l'ordre 01 → 17

Pour chaque exercice :
1. Relis l'énoncé. Pour 01 à 16, compare ensuite avec la solution correspondante dans `exercises/solutions/`, **uniquement pour vérifier** ton travail une fois qu'il est fait.
2. **Exercices d'analyse ou d'exploration** (01–08, 10–13, et toute partie « explique / observe ») :
   - fais réellement les manipulations (curl, journaux, lecture du code) ;
   - rédige `answers/NN - <titre>.md` avec tes constats, les commandes exécutées, les résultats obtenus (codes HTTP, extraits de réponses) et les fichiers et lignes de code concernés ;
   - ne copie pas la solution : reformule à partir de ce que tu as observé toi-même.
3. **Exercices d'implémentation** (09, 14, 17, et toute autre partie qui demande du code) : code, compile, teste.
4. **Ex 15 (tests)** : écris les tests JUnit 5 dans `backend/src/test/java/...`, sans Mockito puisqu'il n'est pas dans le pom. Utilise des sous-classes ou des `java.lang.reflect.Proxy`, comme le permet le pom avec `resteasy-core` en test.
5. **Ex 16 (sécurité)** : identifie la mauvaise configuration, explique son impact concret (scénario d'attaque, code HTTP avant et après), corrige-la de la façon la plus ciblée possible, puis prouve la correction avec une requête qui était acceptée avant et qui est refusée après.
6. **Ex 17 (BoardMember)** : respecte à la lettre les exigences R1–R10 et F1–F5. En particulier :
   - le propriétaire n'est jamais stocké dans `BoardMember` ;
   - les actions réservées au propriétaire (renommer, supprimer, gérer les membres) renvoient **403** à un membre, et ce contrôle passe **avant** la validation, pour qu'un membre ne reçoive jamais un 400 ;
   - un doublon, ou le propriétaire lui-même, renvoie 400 ;
   - la suppression d'un tableau supprime aussi ses membres ;
   - les noms d'utilisateur sont normalisés en minuscules ;
   - `GET /api/boards` fusionne les tableaux possédés et partagés, sans doublon ;
   - côté frontend, le panneau des membres est visible par tous, les contrôles par le propriétaire ou un admin seulement, et le bouton Delete est masqué aux membres ;
   - si l'exercice 09 a ajouté un bouton de renommage, il doit lui aussi être masqué aux membres.
7. Après chaque exercice, lance la **boucle de vérification** (section 4). Ne passe à l'exercice suivant que si tout est vert, puis fais le commit et mets à jour `PROGRESS.md`.

## 4. Boucle de vérification (obligatoire, à répéter jusqu'à zéro erreur)

```bash
cd backend  && mvn -q -B test                 # compilation + tests unitaires
cd frontend && npx ng build                   # compilation Angular stricte
cd frontend && npm test                       # en bash ; si Chrome/Puppeteer est indisponible, documente-le
bash scripts/test-sharing.sh                  # tests API de bout en bout (dès l'exercice 17)
```

- Après une modification d'entité, redémarre le backend pour que Liberty crée les tables manquantes. Si le schéma est incohérent, utilise `docker compose down -v`, puis relance.
- Ne désactive **jamais** un test pour le faire passer. Corrige le code, ou explique pourquoi le test était faux.
- `scripts/test-sharing.sh` doit couvrir au minimum : R2–R5, R6, R7 (lire, créer, modifier, déplacer et supprimer une carte et une colonne en tant que membre), R8 (renommer, supprimer, ajouter ou retirer des membres en tant que membre → 403), R9 (étranger → 403), R10, le bypass admin (carol), et la révocation immédiate (bob retiré → 403 à sa requête suivante). Il affiche OK ou KO par ligne et renvoie un code de sortie différent de 0 en cas d'échec.

## 5. Livrables finaux

1. Le code complet sur la branche `complete-project`, avec un commit par exercice.
2. `answers/` : une réponse par exercice d'analyse.
3. `PROGRESS.md` : le tableau final (tout en ✅ ou justifié), les hypothèses, les problèmes rencontrés et leur solution.
4. `PR_WRITEUP.md` pour l'exercice 17, en anglais, une demi-page :
   - comment `BoardAccess` distingue les actions réservées au propriétaire de celles ouvertes à tout collaborateur ;
   - un cas limite d'autorisation et la façon dont il est traité (par exemple, un membre qui tente de retirer un autre membre ou de se retirer lui-même).
5. `TEST_REPORT.md` : la sortie brute des 4 commandes de la section 4, lors de la dernière exécution.
6. Un récapitulatif final dans le terminal : ce qui est fait, ce qui ne l'est pas et pourquoi, et les commandes pour que je vérifie moi-même.

## 6. Quand t'arrêter et me demander

- Avant de commencer à coder (validation du plan de la section 2).
- Si un exercice exige une décision qui n'est pas dans l'énoncé et qui change le comportement visible de l'application.
- Si tu dois modifier un fichier de sécurité ou d'infrastructure en dehors de l'exercice 16.
- Si un problème d'environnement (Docker, ports, réseau, proxy d'entreprise, inspection TLS) persiste après **3 tentatives** de correction différentes.
- Si tu as besoin d'une nouvelle dépendance.

Dans tous les autres cas, continue jusqu'au bout sans demander de confirmation.
