# 13 — Verify JWT Roles and Board Ownership

> **Conditions.** Pas de Keycloak ni de Liberty dans cette session (voir `PROGRESS.md`), donc aucun jeton réel. Les statuts sont ceux attendus d'après le code. La règle d'appartenance elle-même est **prouvée par des tests exécutés** : `BoardAccessTest` (exercice 15) et le scénario API complet `scripts/test-sharing.sh` (exercice 17, à lancer dans le Dev Container).
>
> Commandes à utiliser (aucune valeur de jeton affichée) :
> ```bash
> ALICE_TOKEN=$(bash scripts/token.sh alice); BOB_TOKEN=$(bash scripts/token.sh bob); ADMIN_TOKEN=$(bash scripts/token.sh carol)
> code() { curl -s -o /dev/null -w '%{http_code}\n' "$@"; }
> ```

## 2. Authentification sur `GET /api/boards`

| Scénario | Catégorie | Statut attendu |
|---|---|---:|
| Sans jeton | non authentifié | **401** |
| Jeton d'Alice | utilisateur | **200** (ses tableaux) |
| Jeton de Bob | utilisateur | **200** (ses tableaux) |
| Jeton admin (carol) | administrateur | **200** (tous les tableaux, `findAllSortedByName`) |

## 3. Appartenance

Alice crée un tableau (`POST /api/boards` → `201`, on ne note que l'`id`, ex. `$ID`).

| Appelant | Opération | Attendu | Pourquoi |
|---|---|---|---|
| Alice | lecture | autorisé, **200** | `owner == "alice"` |
| Bob | lecture | refusé, **403** | `requireBoardAccess` lève `ForbiddenException` |
| Bob | `PUT` (renommage) | refusé, **403** | même contrôle via `accessibleBoard` |
| Bob | `DELETE` | refusé, **403** | même contrôle |
| Admin | lecture | autorisé, **200** | `currentUser.isAdmin()` court-circuite |

Corps du 403 : `{"error":"Board <id> belongs to someone else"}` (`ForbiddenExceptionMapper`).

**Subtilité :** dans `updateBoard(@PathParam long id, @Valid Board board)`, Bean Validation s'exécute **avant** le corps de la méthode. Un `PUT` de Bob avec `{"name":""}` reçoit donc `400`, et non `403`. Cela ne fuit pas de donnée, mais l'ordre « validation puis autorisation » est à garder en tête. L'exercice 17 inverse explicitement cet ordre pour les endpoints de membres.

## 4. Code de sécurité (refus de Bob)

| Étape | Source |
|---|---|
| Validation du jeton activée par | `@LoginConfig(authMethod = "MP-JWT")` — `KanbanApplication.java:26`, avec `mp.jwt.verify.publickey.location / issuer / audiences` — `microprofile-config.properties:12-22` |
| Rôle global requis déclaré par | `@RolesAllowed({ CurrentUser.USER, CurrentUser.ADMIN })` — `BoardResource.java:45` (idem `BoardListResource:41`, `CardResource:46`) |
| Nom d'utilisateur interprété par | `CurrentUser.name()` (claim `preferred_username`, repli `sub`) — `CurrentUser.java:39-43` |
| Appartenance vérifiée par | `BoardAccess.requireBoardAccess(board)` — `BoardAccess.java:38-42`, appelé par `BoardResource.accessibleBoard` (lignes 151-155) |
| Réponse 403 produite par | `ForbiddenExceptionMapper.toResponse` — `ForbiddenExceptionMapper.java:27-33` |

## 5. `owner` fourni par le client

```bash
curl -s -X POST http://localhost:9080/api/boards -H "Authorization: Bearer $ALICE_TOKEN" \
  -H 'Content-Type: application/json' -d '{"name":"Spoof","owner":"bob"}' | jq .owner
```
Résultat attendu : `"alice"`. `createBoard` exécute `board.setOwner(currentUser.name())` (`BoardResource.java:96`) **après** la désérialisation, ce qui écrase la valeur du client. C'est correct : le jeton est signé par Keycloak et vérifié par le serveur, alors que le JSON est écrit par le client, qui peut y mettre n'importe quoi.

## Bilan

- **Alice et Bob ont tous deux le rôle `user` :** un rôle est une permission *globale* (« peut utiliser l'application »), pas une permission sur une donnée.
- **Bob n'accède pourtant pas au tableau d'Alice :** la règle par objet (`owner`) est vérifiée en plus du rôle, dans `BoardAccess`.
- **L'admin y accède :** `isAdmin()` (`groups` contient `admin`) court-circuite la règle par objet, volontairement.
- **401 vs 403 :** `401` = « je ne sais pas qui vous êtes » (pas de jeton ou jeton invalide) ; `403` = « je sais qui vous êtes, et c'est non ».
- **Le JSON n'est pas une source d'identité :** il est entièrement contrôlé par l'appelant. Seule l'identité extraite d'un jeton dont la signature, l'émetteur, l'audience et l'expiration ont été vérifiés fait foi.

## Extension : 404 vs 403

`accessibleBoard` fait `findById` (→ `404` si absent) **avant** le contrôle d'accès (→ `403`). Un identifiant inconnu donne donc `404`, et le tableau réel d'autrui `403`. La différence **révèle l'existence** de l'identifiant : en itérant sur les ids, Bob peut compter les tableaux de la plateforme. Alternative plus discrète : répondre `404` dans les deux cas (« n'existe pas *pour vous* »). Le projet a choisi `403`, plus clair pour le diagnostic et cohérent avec les tests et l'exercice 17 (R8 exige explicitement `403`, « not 404 »).
