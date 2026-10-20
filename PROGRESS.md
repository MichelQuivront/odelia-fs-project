# PROGRESS — odelia-fs-project

Branche : `complete-project` (depuis `main` @ `faff700`), un commit `exNN:` par exercice, poussée sur `origin`.
État : **17/17 exercices traités**. Mise à jour du 2026-10-20 : backend recompilé contre les vraies API et 27/27 tests verts, scénario de partage 56/56 et ex 13/14 18/18 contre la vraie stack (voir `TEST_REPORT.md` §C). Code compilé et testé (backend 27/27, frontend 27/27), **avec une réserve d'environnement** : la stack (Liberty + PostgreSQL + Keycloak) n'a pas pu être lancée dans cette session. Ce qu'il reste à exécuter de ton côté est listé en §6.

## 1. Environnement

| Élément | Attendu | Constaté | Statut |
|---|---|---|---|
| Lieu d'exécution | Dev Container / hôte | Conteneur cloud Claude (Ubuntu 24.04, root), **pas** le Dev Container ; l'ordinateur lié (Windows) n'expose pas de shell | ℹ️ |
| `java -version` | 21 | OpenJDK 21.0.12 | ✅ |
| `mvn -v` | présent | Maven 3.9.11 | ✅ (mais voir Maven Central) |
| `node -v` | ≥ 20.19 / ≥ 22.12 | v22.22.0 (npm 10.9.4) | ✅ |
| `docker compose version` | présent | Compose v5.5.1 ; démon arrêté au départ → démarré avec `dockerd` | ✅ |
| `docker compose up -d postgres keycloak` | conteneurs UP | `quay.io` et `registry-1.docker.io` refusés (403, politique du proxy) | ❌ |
| Maven Central | joignable | `repo.maven.apache.org` / `repo1.maven.org` refusés (403) | ❌ |
| Chrome for Testing (Puppeteer) | joignable | `storage.googleapis.com` refusé (403) | ❌ → contourné |
| `scripts/token.sh` | écrit | ✅ (alice/bob/carol, password grant, `localhost:8081`) | ✅ |
| `npm ci` + `npx ng build` | OK | OK (`PUPPETEER_SKIP_DOWNLOAD=1`) | ✅ |

## 2. Inventaire des exercices

| # | Titre | Type | Déjà fait dans le code ? (preuve) | Statut |
|---|---|---|---|---|
| 01 | Inspect an HTTP Exchange | analyse | n/a (observation DevTools/curl de `/health/ready`) | ✅ `answers/01` — valeurs déduites du code + spec MP Health (Liberty non lançable) |
| 02 | Launch and Verify the Kanban Stack | analyse | n/a | ✅ `answers/02` — `ng serve` observé ; échecs d'environnement documentés selon la méthode de l'énoncé |
| 03 | Trace a Kanban Request End to End | analyse | n/a — chaîne : `board-list.component.ts:44` → `board.service.ts:30` → `BoardResource.java:91-106` → `BoardRepository` | ✅ `answers/03` — trace complète ; proxy `/api` → 9080 **observé** (`ECONNREFUSED` dans le journal `ng serve`) |
| 04 | Inspect HTML and CSS | analyse | n/a — `board-list.component.html` / `.css` | ✅ `answers/04` — depuis templates/CSS (inspecteur impossible : pas de login) |
| 05 | Diagnose a Service Failure | analyse | n/a | ✅ `answers/05` — scénarios A, B, D **réellement observés** (curl + Chromium/Playwright) ; C analysé. Constat : Keycloak arrêté ⇒ `check-sso` redirige toute la page, contrairement au commentaire de `auth.service.ts:41-43` |
| 06 | Explore the Angular Application | analyse | n/a — `main.ts:5`, `app.config.ts:9-18`, `app.routes.ts:7-11` | ✅ `answers/06` — carte complète du démarrage et des types |
| 07 | Trace Angular Routing and API Calls | analyse | n/a — `proxy.conf.json:2-6`, `environment.ts:4`, `angular.json:70` | ✅ `answers/07` — proxy et redirection `**` partiellement observés |
| 08 | Observe Angular Authentication | analyse | n/a — `auth.service.ts:32-46`, `auth.guard.ts:20`, `auth.interceptor.ts:19-30` | ✅ `answers/08` — requête `/auth?prompt=none&code_challenge_method=S256` observée ; intercepteur prouvé par ses specs (vertes) |
| 09 | Implement Board Rename | implémentation + test | **Partiel** : `BoardService.renameBoard` existe (`frontend/src/app/services/board.service.ts:34-36`), endpoint `PUT /api/boards/{id}` existe (`BoardResource.java:108-115`). **Aucune UI** de renommage (`board-list.component.html:25-36` n'a que Delete) et **aucun** `board-list.component.spec.ts` | ✅ bouton Rename + éditeur inline (`board-list.component.*`), 6 tests dans `board-list.component.spec.ts` ; extensions faites : focus, Échap, Save désactivé pendant la requête, brouillon conservé en cas d'échec |
| 10 | Explore the Jakarta EE Backend | analyse | n/a — `pom.xml`, `server.xml`, `beans.xml`, `KanbanApplication.java:25-34` | ✅ `answers/10` — code lu ; statuts HTTP attendus, à confirmer en Dev Container |
| 11 | Trace a JAX-RS Request | analyse | n/a — `BoardResource.java:91-106`, suppression `:117-128` | ✅ `answers/11` — code lu ; statuts HTTP attendus, à confirmer en Dev Container |
| 12 | Analyze Jakarta Data and Card Movement | analyse | n/a — `CardResource.java:93-119` (move), `:78-87` (delete + renumérotation) | ✅ `answers/12` — code lu ; statuts HTTP attendus, à confirmer en Dev Container |
| 13 | Verify JWT Roles and Board Ownership | analyse / sécurité | n/a — `BoardAccess.java:38-42`, `CurrentUser.java:39-51`, `ForbiddenExceptionMapper.java` | ✅ `answers/13` — code lu ; statuts HTTP attendus, à confirmer en Dev Container |
| 14 | Implement the Current User Endpoint | implémentation | **Non** : aucun `/api/me` (grep vide sur `backend/src` et `frontend/src`) | ✅ `MeResource` + `CurrentUserView` + `CurrentUser.roles()` ; `MeResourceTest` 4/4 ; curl 401/200 à confirmer en Dev Container (`answers/14`) |
| 15 | Test the Board Ownership Rule | test | **Non** : `backend/src/test` n'existe pas. Le pom est prêt : JUnit 5 + surefire 3.5.2 + `resteasy-core` en test (`pom.xml:55-70`, `:88-92`) | ✅ `BoardAccessTest` (3 tests requis + 2 extensions) + `StubCurrentUser` ; 5/5 verts ; 3 mutations de la règle toutes détectées (`answers/15`) |
| 16 | Find the Security Misconfiguration | sécurité / analyse | **Faille absente des vrais fichiers** : CORS limité à `http://localhost:4200` (`server.xml:49-55`) ; issuer `http://localhost:8081/realms/kanban` (`microprofile-config.properties:17`) ; aucun `ExceptionMapper<Exception>` applicatif (seul `ForbiddenExceptionMapper`) ; aucun secret dans `docker-compose.yml`. Les 4 snippets de l'énoncé sont des variantes hypothétiques | ✅ `answers/16` — 4 extraits analysés (OWASP, risque, correctif) ; **aucune faille dans les fichiers réels, donc aucun fichier de sécurité modifié** ; requêtes de preuve fournies pour le Dev Container |
| 17 | Implement Board Sharing (BoardMember) | implémentation + sécurité | **Non appliqué** : pas d'entité `BoardMember` (seule mention : commentaire `BoardAccess.java:22`) ; `requireBoardAccess` est owner-only (`BoardAccess.java:38-42`) ; `GET /api/boards` ne renvoie que les tableaux possédés (`BoardResource.java:74-78`) ; pas de `scripts/`. Le script `apply-exercise17.sh` (racine) **n'a pas été exécuté** | ✅ backend R1–R10 (`BoardMember`, `BoardMemberRepository`, `BoardAccess` à 2 niveaux, `BoardResource`), frontend F1–F5 (`board-members`, liste, détail), `BoardResourceTest` + `BoardAccessTest` (backend 27/27), specs Angular (27/27), `scripts/test-sharing.sh` (56 contrôles, **56/56 OK contre la vraie stack le 2026-10-20**), `PR_WRITEUP.md` |

## 3. `apply-exercise17.sh` : comment il a été utilisé

Le script **n'a pas été exécuté** : il aurait basculé sur une autre branche (`exercise-17-board-sharing`), écrasé l'UI de renommage (ex 09) et les tests de l'ex 15, et lancé `mvn`. Il a servi de **référence** :
- repris **tels quels** (extraits mécaniquement du script) : `BoardMember.java`, `BoardMemberRepository.java`, `MemberCommand.java`, `board-members.component.{ts,html,css}` ;
- **fusionnés à la main** : `BoardAccess`, `BoardResource`, `board-list.component.*`, `board-detail.component.*`, `board.service.ts`, `models/board.ts`, `BoardAccessTest` ;
- **corrigé / complété par rapport au script** :
  - `updateBoard` gardait `@Valid` → un membre envoyant un nom vide recevait **400** au lieu de 403 (contraire au CLAUDE.md §3.6). Désormais autorisation d'abord, puis `Validator` injecté (mêmes contraintes que `Board`) ;
  - bouton **Rename** (ex 09) masqué aux membres, en plus de Delete ;
  - styles `.error`/`.muted`/boutons ajoutés au panneau des membres (le CSS du détail ne le traverse pas : encapsulation) ;
  - `BoardResourceTest` (12 tests) ajouté ; `test-sharing.sh` étendu de 27 à 56 contrôles (R6 sans doublon, R9 multi-endpoints, 403 sur corps invalide, membre qui retire un autre membre, admin qui ajoute/retire, cascade à la suppression).

**Ne relance pas ce script** sur cette branche : il écraserait les fichiers fusionnés.

## 4. Hypothèses

- Aucune hypothèse de données : comptes vérifiés dans `keycloak/kanban-realm.json` (`alice/alice` user, `bob/bob` user, `carol/carol` user+admin ; client `kanban-app` public, password grant activé).
- HYPOTHÈSE (comportement, non tranché par l'énoncé) : ajouter comme membre un nom inconnu de Keycloak est **accepté** (pas d'appel à l'API d'admin Keycloak). La ligne n'ouvre aucun accès tant que personne ne se connecte sous ce nom. Documenté dans `PR_WRITEUP.md`.
- HYPOTHÈSE : `GET /api/me` exige `CurrentUser.USER` (lettre de l'énoncé 14) et non `{USER, ADMIN}` ; sans effet pratique, carol ayant les deux rôles.

## 5. Problèmes rencontrés et solutions

| # | Problème | Diagnostic | Solution |
|---|---|---|---|
| 1 | Démon Docker absent | `docker ps` : `no such file or directory` sur le socket | `dockerd` lancé à la main ✅ |
| 2 | Images PostgreSQL/Keycloak non téléchargeables | proxy : `connect_rejected 403` pour `quay.io`, `registry-1.docker.io` | non contournable (politique) ; observations faites sans stack quand c'était possible (ex 05) |
| 3 | Maven Central inaccessible → pas de `mvn test` | idem pour `repo.maven.apache.org`, `repo1.maven.org` | JUnit 5 + API Bean Validation/Annotations via `apt` ; **stubs** des autres API (JAX-RS, JPA, Jakarta Data, CDI, MP JWT/Health/OpenAPI) écrits hors dépôt avec les signatures réelles ; `javac -Xlint:all` + JUnit Platform |
| 4 | `npm test` : Chrome de Puppeteer absent | CDN Chrome for Testing refusé | `CHROME_BIN` pointé sur le Chromium préinstallé (Playwright) ; mêmes specs, même Karma |
| 5 | `git push` refusé au début (403) | dépôt rattaché en lecture seule | accès en écriture accordé par toi le 2026-10-20 ✅ |
| 6 | Mutations de l'ex 15 « tous verts » au 2e essai | mon script lisait le rapport XML de la suite plateforme, pas celui de Jupiter | lecture de `TEST-junit-jupiter.xml` ; les 3 mutations sont bien détectées |

## 6. Ce qui reste à vérifier de ton côté (Dev Container)

Les points non exécutables ici. Tout le reste est fait et poussé.

```bash
git fetch && git switch complete-project
# 1. vrai build + tests backend (27 tests attendus)
cd backend && mvn -q -B test && cd ..
# 2. frontend
cd frontend && npm ci && npx ng build && npm test && cd ..      # 27 specs attendues
# 3. stack + tests de bout en bout (depuis l'HÔTE pour les jetons : issuer localhost:8081)
docker compose up -d postgres keycloak
cd backend && mvn liberty:dev        # (re)démarrer : Liberty crée la table BOARD_MEMBER
bash scripts/test-sharing.sh; echo "échecs: $?"                 # 56 contrôles, 0 attendu
# 4. preuves manuelles des exercices d'analyse : commandes dans answers/13, 14 et 16
```

Si `mvn test` signalait une différence entre les vraies API et mes stubs (le seul risque résiduel de compilation), c'est dans les tests et non dans le code principal qu'elle apparaîtrait le plus probablement (`UriBuilder.fromUri`, `Validator` simulé par proxy dans `BoardResourceTest`).
