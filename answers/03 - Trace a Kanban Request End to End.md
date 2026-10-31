# 03 — Trace a Kanban Request End to End

> **Conditions.** La requête n'a pas pu être capturée en direct (stack non lançable ici, voir `PROGRESS.md`). Les valeurs viennent de la lecture du code ; les colonnes « attendu » sont à confirmer dans DevTools.

## 1. La requête (création d'un tableau « Trace-03 »)

| Observation | Réponse |
|---|---|
| Action utilisateur | Saisie du nom puis *Create board* (ou Entrée : `(ngSubmit)`) |
| Méthode | `POST` |
| URL visible | `http://localhost:4200/api/boards` (et non 9080) |
| Content-Type | `application/json` (HttpClient sérialise l'objet) |
| Corps | `{"name":"Trace-03"}` |
| Statut | `201 Created` (+ en-tête `Location: http://localhost:9080/api/boards/{id}`, exposé par CORS `exposeHeaders="Location"`) |
| Corps de réponse | `{"id":<n>,"name":"Trace-03","owner":"alice","createdAt":"2026-…"}` (`isNew` absent : `@JsonbTransient`) |
| `Authorization` présent ? | Oui, `Bearer …` (ajouté par l'intercepteur ; valeur non recopiée) |

## 2. Code frontend

| Question | Réponse |
|---|---|
| Composant | `BoardListComponent.createBoard()` — `board-list.component.ts:44-57`, déclenché par `(ngSubmit)` (`board-list.component.html:2`) |
| Service | `BoardService` (`services/board.service.ts`) |
| Méthode | `createBoard(name)` — `board.service.ts:30-32` |
| URL relative | `${environment.apiUrl}/boards` = `/api/boards` (`environment.ts:4`, `board.service.ts:18`) |

**Pourquoi le port 4200 ?** Le navigateur ne parle qu'au serveur de dev Angular. `proxy.conf.json:2-6` déclare que tout chemin commençant par `/api` est retransmis à `http://localhost:9080`, et `angular.json:70` active ce fichier pour `ng serve`. Le transfert se fait **côté serveur** : DevTools ne voit qu'une requête vers 4200. Preuve observée dans cette session, backend arrêté : `curl http://127.0.0.1:4200/api/boards` → `500`, et le journal de `ng serve` affiche `[vite] http proxy error: /api/boards — connect ECONNREFUSED 127.0.0.1:9080`. Le serveur 4200 a bien tenté de joindre 9080.

## 3. Code backend

| Question | Réponse |
|---|---|
| Ressource JAX-RS | `com.odelia.kanban.resource.BoardResource` (`@Path("/boards")`, ligne 43) sous `@ApplicationPath("/api")` (`KanbanApplication.java:25`) |
| Méthode | `createBoard(@Valid Board board)` — `BoardResource.java:91-106` |
| Annotations HTTP | `@POST`, `@Transactional`, hérite de `@Consumes/@Produces(APPLICATION_JSON)` et de `@RolesAllowed({user, admin})` au niveau classe |
| Repository | `BoardRepository.insert(...)` (ligne 97), puis `BoardListRepository.insert(...)` ×3 (lignes 99-101) |
| Entité / table | `Board` → table `BOARD` ; plus trois `BoardList` → table `BOARD_LIST` (« To do », « Doing », « Done ») |

## 4. Effet persistant

1. **Recharger** détruit tout l'état JavaScript (signals, composants). Si le tableau réapparaît, c'est qu'il a été relu par `GET /api/boards` depuis PostgreSQL, et non conservé en mémoire.
2. **Couche de stockage :** le backend. Le repository Jakarta Data, implémenté par Liberty, écrit dans PostgreSQL via la datasource `jdbc/kanban` (`server.xml:39-46`).
3. **Pas de connexion directe du frontend à PostgreSQL :** il faudrait livrer des identifiants de base à chaque navigateur (lisibles par n'importe qui), et on perdrait toutes les règles appliquées au serveur : authentification JWT, contrôle d'appartenance (`BoardAccess`), owner forcé depuis le jeton (`BoardResource.java:96`), validation, transactions. Le navigateur est un client non fiable.

## Trace complète

```text
Browser action           : saisie « Trace-03 » + Create board (ngSubmit)
  -> Angular component   : BoardListComponent.createBoard()           board-list.component.ts:44
  -> Angular service     : BoardService.createBoard(name)              board.service.ts:30
  -> (authInterceptor)   : ajoute Authorization: Bearer …              auth.interceptor.ts:19-30
  -> HTTP method and path: POST /api/boards  (4200 → proxy → 9080)    proxy.conf.json:2-6
  -> JAX-RS resource     : BoardResource.createBoard(@Valid Board)     BoardResource.java:91
  -> Repository          : BoardRepository.insert + BoardListRepository.insert ×3
  -> Entity/table        : Board/BOARD + 3 × BoardList/BOARD_LIST
  -> HTTP response       : 201 Created, Location + JSON du Board (id, owner, createdAt)
  -> Updated UI          : boards.update([...boards, board].sort(...)) → le @for se re-rend
```

## Extension : suppression

`DELETE /api/boards/{id}` : **pas de corps** de requête (`board.service.ts:38-40`), réponse **`204 No Content` sans corps** (`BoardResource.java:117-128`). Le frontend retire le tableau localement (`board-list.component.ts:67-70`) au lieu de lire une réponse. La création renvoie au contraire `201` avec la ressource créée et un `Location`.
