# 05 — Diagnose a Service Failure

> **Conditions.** Les scénarios A, B et D ont été **réellement observés** dans cette session : le frontend tourne (`ng serve`), alors que le backend et Keycloak sont, de fait, indisponibles. L'observation a été faite avec `curl` et un Chromium headless piloté par Playwright, en capturant les requêtes et leurs échecs. Le scénario C (PostgreSQL) n'a pas pu être reproduit, faute d'image PostgreSQL ; il est analysé à partir du code.

## Scénario A — backend arrêté (observé)

| Question | Réponse |
|---|---|
| Symptôme | les appels API échouent ; la page Angular elle-même se charge |
| Premier point de défaillance | le saut proxy 4200 → 9080 |
| Commande | `curl -si http://127.0.0.1:4200/api/boards` |
| Statut | **`HTTP/1.1 500 Internal Server Error`**, `Content-Type: text/plain`, corps vide |
| Processus | Liberty (`mvn liberty:dev`) absent du port 9080 |
| Journal | `ng serve` : `[vite] http proxy error: /api/boards` / `Error: connect ECONNREFUSED 127.0.0.1:9080` ; `curl http://127.0.0.1:9080/health/ready` → connexion refusée |
| Hypothèse | rien n'écoute sur 9080 |
| Correction | relancer `cd backend && mvn liberty:dev` |
| Preuve de rétablissement | `/health/ready` → `200 {"status":"UP",…}`, puis les appels `/api` repassent en 200 |

Point clé : le **navigateur voit un 500 venant du port 4200**, pas une erreur réseau. C'est le proxy de dev qui le fabrique. Le journal de `ng serve` dit la vérité (`ECONNREFUSED`), pas l'onglet Network.

## Scénario B — frontend arrêté (observé)

`curl http://127.0.0.1:4200/` → `curl: (7) Failed to connect … Couldn't connect to server`. Dans Chromium : `page.goto: net::ERR_CONNECTION_REFUSED at http://127.0.0.1:4200/`. Aucune requête HTTP n'aboutit : c'est la page **d'erreur du navigateur**, pas une page de l'application. Correction : `npm start`.

## Scénario C — PostgreSQL indisponible (non reproductible ici)

Comportement attendu d'après le code : `DatabaseReadinessCheck.call()` attrape l'exception de `getConnection()` et renvoie `down()` avec `withData("error", …)` (`DatabaseReadinessCheck.java:30-36`) → `/health/ready` passe à **`503`** avec `{"status":"DOWN","checks":[{"name":"kanban-database","status":"DOWN","data":{"error":"…Connection refused…"}}]}`. Les appels `/api` échouent en `500`, et la console Liberty journalise des erreurs JDBC. Après `docker start kanban-postgres`, la sonde revient UP **sans redémarrer Liberty** (le pool de connexions se reconnecte).

## Scénario D — Keycloak indisponible (observé)

| Question | Réponse |
|---|---|
| Symptôme | **la page entière de l'application est remplacée** par « This site can't be reached — localhost refused to connect — ERR_CONNECTION_REFUSED » |
| Première URL en échec | `GET http://localhost:8081/realms/kanban/protocol/openid-connect/auth?client_id=kanban-app&redirect_uri=…&prompt=none&code_challenge_method=S256` → `net::ERR_CONNECTION_REFUSED` |
| Processus | conteneur Keycloak (port 8081) |
| Hypothèse | `keycloak.init({ onLoad: 'check-sso', checkLoginIframe: false })` sans `silentCheckSsoRedirectUri` fait une **redirection pleine page** (`prompt=none`) vers Keycloak, et non un appel en arrière-plan |
| Correction | `docker start kanban-keycloak` (ou `docker compose up -d keycloak`) |
| Rétablissement | l'aller-retour `prompt=none` revient sur `localhost:4200/#state=…`, puis le guard redirige vers l'écran de connexion |

**Constat notable :** le commentaire de `auth.service.ts:41-43` (« A Keycloak that is down must not take the whole app down ») est **contredit par l'observation**. Le `try/catch` autour de `init()` ne peut rien attraper : le navigateur a déjà quitté la page avant l'échec. Observé sur `/`, `/boards/3` et `/does-not-exist`. La correction (hors périmètre ici, car elle change le comportement visible) serait d'ajouter `silentCheckSsoRedirectUri` (vérification via iframe) pour que l'échec reste confiné.

## Comparaison des pannes

1. **Frontend arrêté vs backend arrêté :** sans frontend, *rien* ne se charge (erreur réseau du navigateur sur 4200). Sans backend, la coquille Angular se charge (HTML/JS servis par 4200) et seules les requêtes `/api` échouent, transformées en **500 par le proxy**.
2. **Utilité de la sonde de disponibilité :** elle isole une dépendance (la base) en un appel, sans authentification (`server.xml:64-66`), et retourne un statut exploitable par Docker ou un orchestrateur.
3. **Le navigateur est plus utile** pour ce que voit l'utilisateur : quelle URL échoue, redirections (le `prompt=none` vers 8081 du scénario D), CORS, en-têtes.
4. **Les journaux serveur sont plus utiles** pour la cause réelle derrière un statut générique : le `ECONNREFUSED 127.0.0.1:9080` caché derrière le 500 du scénario A, une erreur JDBC, un jeton refusé (issuer, audience).
5. **Tout redémarrer masque la cause :** la panne disparaît sans qu'on sache quel composant était en cause. Elle reviendra, et on aura perdu les journaux et l'état qui l'expliquaient.
