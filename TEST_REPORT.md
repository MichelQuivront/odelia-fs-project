# TEST_REPORT

Dernière exécution : 2026-10-20T09:20:11+02:00, commit `602e709` (branche `complete-project`).

Cette session tourne dans un conteneur cloud dont le proxy sortant **refuse** Maven Central, Docker Hub, quay.io et le CDN Chrome for Testing (statut du proxy : `connect_rejected … 403`, détails dans `PROGRESS.md`). La partie A donne la sortie brute des **4 commandes exactes** du `CLAUDE.md` §4 : elles échouent toutes pour cette raison, aucune pour une erreur de code. La partie B donne la sortie brute de la **boucle de remplacement** réellement exécutée (`verify.sh`, hors dépôt) :

| Commande du CLAUDE.md | Remplacement exécuté ici | Ce qui n'est PAS couvert |
|---|---|---|
| `mvn -q -B test` | `javac --release 21 -Xlint:all` du code principal contre des stubs d'API Jakarta/MicroProfile écrits à la main (signatures réelles), puis JUnit Platform 1.9.1 / Jupiter 5.10 (paquets Ubuntu) sur `src/test` | compilation contre les *vraies* API, déploiement Liberty (génération Jakarta Data, création des tables), RESTEasy réel dans les tests |
| `npx ng build` | identique | — |
| `npm test` | `ng test --watch=false` avec `CHROME_BIN` = Chromium préinstallé (Playwright) au lieu de celui de Puppeteer | — (mêmes specs, même Karma) |
| `bash scripts/test-sharing.sh` | `bash -n` + `shellcheck -S style` | **l'exécution** (il faut Keycloak + PostgreSQL + Liberty) |

**À relancer dans le Dev Container** pour clore la vérification : voir la fin de `PROGRESS.md`.

## A. Les 4 commandes exactes (sortie brute)

### `cd backend && mvn -q -B test`
```text
[ERROR] Plugin org.apache.maven.plugins:maven-resources-plugin:3.3.1 or one of its dependencies could not be resolved:
[ERROR] 	The following artifacts could not be resolved: org.apache.maven.plugins:maven-resources-plugin:pom:3.3.1 (absent): Could not transfer artifact org.apache.maven.plugins:maven-resources-plugin:pom:3.3.1 from/to central (https://repo.maven.apache.org/maven2): repo.maven.apache.org: Name or service not known
[ERROR] -> [Help 1]
[ERROR]
[ERROR] To see the full stack trace of the errors, re-run Maven with the -e switch.
[ERROR] Re-run Maven using the -X switch to enable full debug logging.
[ERROR]
[ERROR] For more information about the errors and possible solutions, please read the following articles:
[ERROR] [Help 1] http://cwiki.apache.org/confluence/display/MAVEN/PluginResolutionException
exit=1
```

### `cd frontend && npx ng build`
```text
❯ Building...
✔ Building...
Initial chunk files   | Names         |  Raw size | Estimated transfer size
main-BZTC2LAX.js      | main          | 408.09 kB |               104.34 kB
polyfills-5CFQRCPP.js | polyfills     |  34.59 kB |                11.33 kB
styles-JBDF3Y6A.css   | styles        | 177 bytes |               177 bytes

                      | Initial total | 442.85 kB |               115.85 kB

Application bundle generation complete. [4.218 seconds] - 2026-10-20T07:20:19.112Z

Output location: /home/claude/odelia-fs-project/frontend/dist/frontend

exit=0
```

### `cd frontend && npm test`
```text
> frontend@0.0.0 test
> CHROME_BIN=$(node -e "require('puppeteer').executablePath().then(p => console.log(p))") ng test --watch=false

- Generating browser application bundles (phase: setup)...
√ Browser application bundle generation complete.
20 10 2026 09:20:24.514:INFO [karma-server]: Karma v6.4.4 server started at http://localhost:9876/
20 10 2026 09:20:24.515:INFO [launcher]: Launching browsers ChromeHeadlessNoSandbox with concurrency unlimited
20 10 2026 09:20:24.519:INFO [launcher]: Starting browser ChromeHeadless
20 10 2026 09:20:24.536:ERROR [launcher]: Cannot start ChromeHeadless
	Can not find the binary /root/.cache/puppeteer/chrome/linux-152.0.7977.75/chrome-linux64/chrome
	Please set env variable CHROME_BIN
20 10 2026 09:20:24.536:ERROR [launcher]: ChromeHeadless stdout:
20 10 2026 09:20:24.536:ERROR [launcher]: ChromeHeadless stderr:
√ Browser application bundle generation complete.
√ Browser application bundle generation complete.
exit=1
```

### `bash scripts/test-sharing.sh`
```text
curl: (7) Failed to connect to localhost port 8081 after 0 ms: Couldn't connect to server
exit=2
```

## B. Boucle de remplacement (sortie brute de `verify.sh`)

4 lignes `ERROR: 'Could not …'` ont été retirées de la sortie Karma : ce sont les `console.error` volontaires des tests qui simulent un 400 ou un 403 (`fail()` journalise l'erreur avant de l'afficher). Les lignes de progression `Executed n of 27` sont également retirées ; le total final est conservé.

```text
### [1/4] backend : javac (contre les stubs d'API) + JUnit 5
javac main: OK (20 classes)
╷
├─ JUnit Platform Suite ✔
├─ JUnit Jupiter ✔
│  ├─ BoardResourceTest ✔
│  │  ├─ listingMergesOwnedAndSharedBoardsOnceSortedByName() ✔
│  │  ├─ ownerAddsAMemberNormalizedToLowerCase() ✔
│  │  ├─ deletingABoardDeletesItsMemberships() ✔
│  │  ├─ adminManagesMembersAndOwnerOnlyActions() ✔
│  │  ├─ memberListsMembersStrangerDoesNot() ✔
│  │  ├─ duplicateMemberIs400AndNotStoredTwice() ✔
│  │  ├─ memberCannotRemoveAnotherMember() ✔
│  │  ├─ adminStillSeesEveryBoard() ✔
│  │  ├─ memberGets403NotA400OnEveryOwnerOnlyAction() ✔
│  │  ├─ removalIsImmediateAndUnknownMemberIs404() ✔
│  │  ├─ ownerCannotAddOrRemoveThemselves() ✔
│  │  └─ blankUsernameIs400ForTheOwner() ✔
│  ├─ MeResourceTest ✔
│  │  ├─ userGetsTheirNameAndRoles() ✔
│  │  ├─ responseNeverCarriesTheRawToken() ✔
│  │  ├─ missingGroupsClaimMeansNoRolesNotNull() ✔
│  │  └─ adminRolesAreSortedAndFlagged() ✔
│  └─ BoardAccessTest ✔
│     ├─ otherNonAdminUserIsForbidden() ✔
│     ├─ ownerIsAllowed() ✔
│     ├─ adminBypassesBothLevels() ✔
│     ├─ orphanColumnIsDeniedEvenToItsWouldBeOwner() ✔
│     ├─ memberReachesColumnsThroughTheBoard() ✔
│     ├─ ownerCanCollaborateAndManage() ✔
│     ├─ memberCanCollaborateButNotManage() ✔
│     ├─ removedMemberIsDeniedOnTheNextCheck() ✔
│     ├─ strangerIsDeniedEverywhere() ✔
│     ├─ columnAccessWalksUpToTheBoardOwner() ✔
│     └─ adminIsAlwaysAllowed() ✔
└─ JUnit Vintage ✔

Test run finished after 214 ms
[        27 tests found           ]
[         0 tests skipped         ]
[        27 tests started         ]
[         0 tests aborted         ]
[        27 tests successful      ]
[         0 tests failed          ]

### [2/4] frontend : npx ng build
❯ Building...
✔ Building...
Initial chunk files   | Names         |  Raw size | Estimated transfer size
main-BZTC2LAX.js      | main          | 408.09 kB |               104.34 kB
polyfills-5CFQRCPP.js | polyfills     |  34.59 kB |                11.33 kB
styles-JBDF3Y6A.css   | styles        | 177 bytes |               177 bytes
                      | Initial total | 442.85 kB |               115.85 kB
Application bundle generation complete. [4.421 seconds] - 2026-10-20T07:21:27.847Z
Output location: /home/claude/odelia-fs-project/frontend/dist/frontend

### [3/4] frontend : npm test (Karma, Chromium préinstallé de Playwright)
TOTAL: 27 SUCCESS
√ Browser application bundle generation complete.
√ Browser application bundle generation complete.

### [4/4] scripts/test-sharing.sh
syntaxe bash: OK
shellcheck: OK
exécution : IMPOSSIBLE ici (pas de Keycloak/PostgreSQL/Liberty : images Docker et Maven Central bloqués)

=== résultat global : VERT
exit=0
```

## C. Vérification sur la vraie stack (Dev Container de Michel, 2026-10-20 ~11:25)

| Vérification | Comment | Résultat |
|---|---|---|
| `GET /health/ready` | navigateur intégré → `localhost:9080` | `{"status":"UP","checks":[{"name":"kanban-database","status":"UP"}]}` |
| Compilation backend **contre les vraies API** | Maven 3.9.11 hors ligne + cache `~/.m2` de Michel (jakartaee-web-api 11.0.0, microprofile 7.1, resteasy-core 7.0.0.Final, JUnit 5.11.3), JDK 21 | `Compiling 20 source files` + `Compiling 4 source files` [release 21] : OK |
| Tests JUnit backend | classes compilées par Maven, vrai RESTEasy 7.0.0 sur le classpath, lanceur JUnit Platform (surefire 3.5.x incomplet dans le cache, donc non exécutable hors ligne) | **27/27 verts** |
| `scripts/test-sharing.sh` (56 contrôles) | même scénario rejoué en JavaScript dans le navigateur intégré, appels directs à `localhost:9080/api`, jetons Keycloak réels (`iss=http://localhost:8081/realms/kanban`) | **56 OK, 0 KO** |
| Ex 13/14 (401 sans jeton, `/api/me` ×3, owner forcé, 403 JSON, admin, 404) | idem | **18 OK, 0 KO** |
| Interface Angular (F1–F5, ex 09) en direct | non faite : le navigateur intégré bloque les sous-requêtes vers Keycloak (`ERR_BLOCKED_BY_CLIENT`) et l'extension Chrome n'était pas connectée | couverte par les 27 specs Karma (partie B) |

Bug d'environnement trouvé pendant cette vérification : la copie Windows convertit les `.sh` en CRLF (`core.autocrlf`), ce qui casse `scripts/*.sh` sous bash (`$'\r': command not found`). Corrigé par `.gitattributes` (`*.sh text eol=lf`, commit `19ac06a`).
