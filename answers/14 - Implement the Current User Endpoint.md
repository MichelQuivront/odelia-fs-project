# 14 — Implement the Current User Endpoint

## Ce qui a été fait

| Fichier | Rôle |
|---|---|
| `backend/.../resource/MeResource.java` | `GET /api/me`, `@RequestScoped`, `@Produces(JSON)`, `@RolesAllowed(CurrentUser.USER)`, `@SecurityRequirement("bearerAuth")`, `operationId = getCurrentUser` |
| `backend/.../resource/CurrentUserView.java` | `record CurrentUserView(String username, List<String> roles, boolean admin)` |
| `backend/.../security/CurrentUser.java` | nouvelle méthode `roles()` : le claim `groups` validé, trié, liste vide si absent |
| `backend/src/test/.../resource/MeResourceTest.java` | 4 tests JUnit : un vrai `CurrentUser` alimenté par un faux `JsonWebToken` (`java.lang.reflect.Proxy`) |

Réutilisation : `username` vient de `CurrentUser.name()` (la même interprétation que pour `Board.owner`), `admin` de `CurrentUser.isAdmin()`, `roles` du même claim `groups` que lit `@RolesAllowed`. La ressource ne lit aucun claim elle-même et ne touche jamais la chaîne du jeton.

## Questions de conception

1. **Paquet :** `com.odelia.kanban.resource`, à côté de `MoveCommand`. C'est une forme de l'API REST, pas une règle de sécurité.
2. **Une entité ?** Non : rien n'est persisté. La valeur est recalculée à chaque requête depuis un jeton vérifié ; une table serait une copie qui pourrait diverger de Keycloak.
3. **Champs exposés :** `username`, `roles`, `admin`. Volontairement absents : le jeton brut, `sub` (UUID interne), `exp`, `iss`, l'e-mail. Ils sont inutiles à l'interface, et le jeton brut serait réutilisable par quiconque lit la réponse (journaux, cache).
4. **Ordre des rôles :** déterministe (trié). `getGroups()` renvoie un `Set` sans ordre garanti ; un ordre stable rend le JSON comparable dans les tests et les diffs. Vérifié par `adminRolesAreSortedAndFlagged` (`["admin","user"]`).

`@RolesAllowed(CurrentUser.USER)` suit la lettre de l'énoncé. Dans le realm, `carol` (admin) a aussi le rôle `user` (`kanban-realm.json`), elle passe donc.

## Vérification

**Dans cette session :** compilation (contre les API stubs, voir `PROGRESS.md`) + `MeResourceTest`, 4/4 verts :
- `userGetsTheirNameAndRoles` — `{"username":"alice","roles":["user"],"admin":false}` ;
- `adminRolesAreSortedAndFlagged` — `carol`, `["admin","user"]`, `admin: true` ;
- `missingGroupsClaimMeansNoRolesNotNull` — `roles: []`, jamais `null` ;
- `responseNeverCarriesTheRawToken` — les composants du record sont exactement `username, roles, admin`.

**À exécuter dans le Dev Container** (le 401 et le JSON réel exigent Liberty et Keycloak) :

```bash
curl -i http://localhost:9080/api/me                                               # 401
for u in alice bob carol; do
  curl -si -H "Authorization: Bearer $(bash scripts/token.sh $u)" http://localhost:9080/api/me | sed -n '1p;/^Content-Type/p;$p'
done   # 200, application/json, {"admin":false,"roles":["user"],"username":"alice"} … carol: "admin":true
curl -s http://localhost:9080/openapi | grep -A3 '/api/me'                         # getCurrentUser + schéma CurrentUserView
```

Dans `/openapi`, le schéma généré `CurrentUserView` doit lister `username` (string), `roles` (array of string) et `admin` (boolean), soit exactement les composants du record.
