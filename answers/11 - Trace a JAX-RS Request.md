# 11 — Trace a JAX-RS Request

> **Conditions.** Création non capturée en direct (stack non lançable ici, voir `PROGRESS.md`). Les valeurs sont déduites de `BoardResource.java` et `Board.java` ; à confirmer avec `curl -i` dans le Dev Container (`TOKEN=$(bash scripts/token.sh alice)`).

## 1. Création d'un tableau

```bash
curl -i -X POST http://localhost:9080/api/boards \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Trace-11","owner":"mallory","id":999}'
```

| Observation | Réponse attendue |
|---|---|
| Méthode | `POST` |
| Chemin complet | `/api/boards` |
| Content-Type de la requête | `application/json` |
| JSON envoyé | `{"name":"Trace-11","owner":"mallory","id":999}` (`owner` et `id` ajoutés exprès) |
| Statut | `201 Created`, `Location: http://localhost:9080/api/boards/<n>` |
| JSON renvoyé | `{"id":<n>,"name":"Trace-11","owner":"alice","createdAt":"<horodatage serveur>"}` |

## 2. Assemblage du chemin

```text
application path:  /api      @ApplicationPath("/api")   KanbanApplication.java:25
+ resource path:   /boards   @Path("/boards")           BoardResource.java:43
+ method path:     (aucun)   @POST sans @Path           BoardResource.java:91
= final URL:       /api/boards   (contexte racine "/", server.xml:71)
```

## 3. Logique de la ressource (`createBoard`, `BoardResource.java:91-106`)

Avant le corps de la méthode : MP-JWT valide le jeton, `@RolesAllowed({user, admin})` vérifie le rôle, JSON-B désérialise en `Board`, puis `@Valid` applique `@NotBlank @Size(max=120)` sur `name` (sinon `400`).

| Étape | Opération |
|---:|---|
| 1 | `board.setId(null)` : l'`id` du client est ignoré (l'IDENTITY de la base décidera) |
| 2 | `board.setCreatedAt(LocalDateTime.now())` : horodatage serveur |
| 3 | `board.setOwner(currentUser.name())` : propriétaire tiré du jeton (`preferred_username`) |
| 4 | `Board created = boards.insert(board)` : `BoardRepository` |
| 5 | boucle `lists.insert(new BoardList(created.getId(), DEFAULT_LISTS.get(i), i))` ×3, puis `Response.created(<URI>).entity(created).build()` |

- **Vient de la requête :** `name` seulement.
- **Vient de l'identité authentifiée :** `owner` (`CurrentUser.name()`, `CurrentUser.java:39-43`).
- **Contrôlé par le serveur :** `createdAt` (et `id`).
- **Repository d'insertion :** `BoardRepository.insert` (hérité de `CrudRepository`).
- **Colonnes créées :** « To do », « Doing », « Done » (`DEFAULT_LISTS`, ligne 51), positions 0, 1, 2.

Le tout est `@Transactional` : si l'insertion d'une colonne échoue, le tableau est annulé lui aussi.

## 4. La réponse

1. **`201` plutôt que `200` :** une ressource a été *créée*. `201 Created` le dit, et l'en-tête `Location` donne son URL canonique (`uriInfo.getAbsolutePathBuilder().path(id)`).
2. **Identifiant généré ?** Oui : `insert` renvoie l'entité avec l'`id` produit par `GenerationType.IDENTITY`.
3. **Valeurs absentes ou non fiables dans la requête :** `id` (forcé à null puis généré), `owner` (`mallory` écrasé par `alice`), `createdAt` (horodatage serveur).
4. **Sans jeton :** `401 Unauthorized`. MP-JWT ne trouve pas d'identité et `@RolesAllowed` refuse avant toute exécution de la méthode.

## Récit

```text
POST JSON {"name":"Trace-11",...}
  -> JAX-RS mapping        /api + /boards + @POST → BoardResource.createBoard
  -> BoardResource method  @Valid Board (400 si nom vide), @Transactional
  -> authenticated owner   setOwner(currentUser.name()) ; id=null ; createdAt=now()
  -> BoardRepository       insert(board) → ligne BOARD, id généré
  -> default BoardList     3 × lists.insert(...) → BOARD_LIST (To do / Doing / Done)
  -> 201 JSON response     Location: /api/boards/<id> + Board JSON
```

## Extension : suppression

`DELETE /api/boards/{id}` → `deleteBoard` (`BoardResource.java:117-128`), `@Transactional` :
1. `accessibleBoard(id)` : `404` si absent, `403` si pas à l'appelant ;
2. pour chaque colonne `lists.findByBoardIdOrderByPositionAsc(id)` : `cards.deleteByListId(column.getId())` ;
3. `lists.deleteByBoardId(id)` ;
4. `boards.delete(existing)` → `204 No Content`.

La cascade est **écrite à la main dans la ressource**, des feuilles vers la racine, faute d'association JPA ou de `ON DELETE CASCADE` (convention rappelée dans le `README.md`).
