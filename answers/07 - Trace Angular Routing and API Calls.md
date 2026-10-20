# 07 — Trace Angular Routing and API Calls

> **Conditions.** Navigation connectée impossible ici (Keycloak indisponible). Le proxy et la route `**` ont été observés partiellement ; le reste vient du code.

## 1. Navigation

| Question | Réponse |
|---|---|
| URL de la liste | `http://localhost:4200/` |
| URL du détail | `http://localhost:4200/boards/<id>` (ex. `/boards/3`) |
| Motif de route | `boards/:id` — `app.routes.ts:9` |
| Composant routé | `BoardDetailComponent` |
| Source de l'identifiant | `this.route.snapshot.paramMap.get('id')` converti par `Number(...)` — `board-detail.component.ts:70` |

Le lien déclencheur est `[routerLink]="['/boards', board.id]"` — `board-list.component.html:26`.

## 2. Un appel API au chargement du détail

| Couche | Fichier et identifiant |
|---|---|
| Méthode du composant | `BoardDetailComponent.reload()` (`board-detail.component.ts:74-90`), appelé par `ngOnInit` |
| Méthode du service | `BoardService.getLists(boardId)` — `board.service.ts:42-44` |
| URL relative | `/api/boards/3/lists` |
| Méthode HTTP | `GET` |
| Requête visible | `http://localhost:4200/api/boards/3/lists` |
| Port backend cible | `9080` |

Au même chargement partent aussi `GET /api/boards/3` (`getBoard`) puis un `GET /api/lists/{id}/cards` par colonne, en parallèle via `forkJoin` (`board-detail.component.ts:241`).

## 3. Le proxy

1. **URL de base de l'API :** `'/api'`, relative — `environment.ts:4`.
2. **Chemins proxifiés :** `/api` et `/health` — `proxy.conf.json:2-10`.
3. **Cible :** `http://localhost:9080` (`changeOrigin: true` pour `/api`).
4. **Pourquoi 4200 dans Network :** le navigateur n'envoie la requête qu'au serveur de dev, qui la relaie côté serveur. Observé ici : backend arrêté, `GET 4200/api/boards` → `500` et journal `ng serve` : `http proxy error: /api/boards … ECONNREFUSED 127.0.0.1:9080`.
5. **Pas l'architecture de production :** `proxyConfig` n'est branché que sur la configuration `development` du builder `dev-server` (`angular.json:68-71`). `ng build` produit des fichiers statiques sans proxy. En production, il faut un reverse proxy (nginx, ingress) qui serve `/` et `/api` sous la même origine, ou bien de vrais appels cross-origin couverts par CORS (`server.xml:49-55`).

## Chaîne complète

```text
Click board        <a [routerLink]="['/boards', board.id]">        board-list.component.html:26
  -> route match   { path: 'boards/:id', canActivate: [authGuard] }  app.routes.ts:9
  -> component     BoardDetailComponent.ngOnInit → reload()          board-detail.component.ts:69-90
  -> service       BoardService.getBoard / getLists / getCards       board.service.ts:26-48
  -> /api request  GET /api/boards/3/lists (+ Bearer par authInterceptor)
  -> dev proxy     ng serve: /api → http://localhost:9080            proxy.conf.json
  -> backend       BoardResource.listColumns → BoardAccess → BoardListRepository
```

## Extension : `/does-not-exist`

La règle `{ path: '**', redirectTo: '' }` (`app.routes.ts:10`) renvoie vers `/`, qui est gardée par `authGuard`. Observé ici : comme `AuthService.init()` s'exécute **avant** le routeur, l'aller-retour Keycloak est tenté avant même que la route soit résolue. La requête partie vers Keycloak portait `redirect_uri=http://127.0.0.1:4200/does-not-exist` ; la redirection `**` n'intervient qu'au retour.
