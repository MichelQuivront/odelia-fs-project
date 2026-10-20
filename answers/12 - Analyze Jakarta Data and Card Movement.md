# 12 — Analyze Jakarta Data and Card Movement

> **Conditions.** La partie 3 (capture d'un `PATCH`) n'a pas pu être faite en direct (stack non lançable ici). Le format de la requête est néanmoins **vérifié par un test exécuté** dans cette session : `board-detail.component.spec.ts` « PATCHes the card when it is dropped into another column » attend exactement `{ targetListId: 2, position: 0 }` (16/16 tests verts). Les parties 1, 2 et 4 viennent du code.

## 1. Entités

| Entité | Identifiant | Référence au parent | Champ d'ordre |
|---|---|---|---|
| `Board` | `Long id` (IDENTITY) | aucune (`owner` = nom d'utilisateur, pas une FK) | aucun ; tri par `name` à la lecture |
| `BoardList` | `Long id` | `long boardId` (colonne `BOARD_ID`) | `int position` (colonne `LIST_POSITION`) |
| `Card` | `Long id` | `long listId` (colonne `LIST_ID`) | `int position` (colonne `CARD_POSITION`, 0-based) |

1. **Associations objet ou identifiants scalaires ?** Identifiants scalaires : aucun `@ManyToOne`/`@OneToMany`.
2. **Avantage pour le JSON :** il est plat et sans cycle (`{"id":4,"listId":2,"title":"…"}`), sans chargement paresseux qui exploserait à la sérialisation ni graphe d'objets à envoyer. Il ressemble exactement à ce que le frontend manipule (`models/board.ts`).
3. **Surcoût pour l'autorisation :** une carte ne « sait » pas à qui elle appartient. `BoardAccess` doit **remonter à la main** : `card.listId` → `lists.findById` → `column.boardId` → `boards.findById` → `owner` (`BoardAccess.java:44-62`), soit deux requêtes de plus. Il faut aussi décider du cas orphelin (parent introuvable) : ici, refus (`orphan()` → `403`).

## 2. Repositories

| Repository | Interface de base | Une requête dérivée |
|---|---|---|
| `BoardRepository` | `CrudRepository<Board, Long>` | `findByOwnerOrderByNameAsc(String owner)` (à côté de `findAllSortedByName()`, qui utilise des annotations `@Find @OrderBy("name")`) |
| `BoardListRepository` | `CrudRepository<BoardList, Long>` | `findByBoardIdOrderByPositionAsc(long boardId)` |
| `CardRepository` | `CrudRepository<Card, Long>` | `findByListIdOrderByPositionAsc(long listId)` (et `countByListId`, `deleteByListId`) |

Preuves :
- **Ce sont des interfaces :** `public interface BoardRepository extends CrudRepository<…>`.
- **Jamais instanciées :** `grep -rn "new .*Repository" backend/src/main/java` ne renvoie rien ; elles sont **injectées** (`@Inject BoardRepository boards;`).
- **Pas d'`EntityManager` :** `grep -rn EntityManager backend/src/main/java` ne renvoie rien.
- **Liberty fournit l'implémentation :** `@Repository(dataStore = "jdbc/kanban")` est traité par la feature Jakarta Data de `webProfile-11.0`, qui génère un bean CDI pour chaque interface. Aucune classe d'implémentation n'existe dans `src/`. La compilation de cette session contre les seules API le confirme : `javac` produit 15 classes, et aucune implémentation de repository.

| Préoccupation | Technologie |
|---|---|
| Lier l'état Java aux lignes de la base | **Jakarta Persistence (JPA)** : `@Entity`, `@Table`, `@Column`, `@Id`, `@GeneratedValue` |
| Exprimer les opérations de repository | **Jakarta Data** : `CrudRepository`, requêtes dérivées du nom, `@Find`/`@OrderBy` |

## 3. Déplacement d'une carte

| Observation | Réponse |
|---|---|
| Champs du corps | `targetListId` (long), `position` (int, `@PositiveOrZero`) — `MoveCommand.java:13` |
| Numérotation des positions | à partir de **0** |
| Résultat côté colonne source | les cartes restantes sont renumérotées 0, 1, 2… sans trou |
| Résultat côté colonne cible | la carte est insérée à l'index demandé (borné à la taille), les suivantes décalées de +1 |

## 4. L'algorithme (`CardResource.move`, lignes 93-119)

| Invariant | Opération qui le protège |
|---|---|
| Le tableau source est accessible | `accessibleCard(id)` → `access.requireCardAccess(card)` (ligne 98) |
| Le tableau cible est accessible | `lists.findById(targetListId)` (404 sinon) + `access.requireColumnAccess(targetColumn)` (lignes 102-104) |
| La position est valide | `@PositiveOrZero` + `@Valid` (400 si négative), puis `Math.max(0, Math.min(position, target.size()))` (ligne 107) qui borne une valeur trop grande |
| Positions source contiguës | si la colonne change : `renumber(remaining(sourceListId, id))` (lignes 115-117) |
| Positions cible contiguës | `remaining(targetListId, id)` (la carte retirée si même colonne), `target.add(index, card)`, `renumber(target)` (lignes 106-110) |
| La carte reçoit sa colonne et sa position | `card.setListId(targetListId)` + position fixée par `renumber`, puis `cards.save(card)` **inconditionnel** (ligne 113) : une carte qui garde l'index 2 en changeant de colonne ne serait pas « changée » pour `renumber` |

Tout est dans une seule transaction (`@Transactional`) : soit tout le réordonnancement est appliqué, soit rien.

## Pourquoi `setListId` + `save` ne suffit pas

```java
card.setListId(targetListId);
cards.save(card);
```

1. **Trou dans la source :** les cartes après elle gardent leurs positions (0, 2, 3).
2. **Collision dans la cible :** sa vieille `position` peut coïncider avec celle d'une carte existante, et l'ordre devient indéterminé.
3. **Position demandée ignorée :** on ne peut pas la déposer en tête.
4. **Pas de contrôle d'accès sur la cible :** on pourrait déplacer sa carte dans la colonne d'un autre utilisateur (seule la source aurait été vérifiée).

## Extension : suppression au milieu

`CardResource.deleteCard` (lignes 78-87) : `cards.delete(existing)` puis `renumber(remaining(existing.getListId(), existing.getId()))`. Les cartes restantes sont relues dans l'ordre et chaque position est réécrite égale à son index, ce qui referme le trou.
