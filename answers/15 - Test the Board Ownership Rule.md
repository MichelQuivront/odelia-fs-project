# 15 — Test the Board Ownership Rule

## Ce qui a été fait

- `backend/src/test/java/com/odelia/kanban/security/StubCurrentUser.java` : sous-classe de `CurrentUser` qui surcharge `name()` et `isAdmin()`.
- `backend/src/test/java/com/odelia/kanban/security/BoardAccessTest.java` :
  1. `ownerIsAllowed` — alice sur son tableau → pas d'exception ;
  2. `otherNonAdminUserIsForbidden` — bob → `ForbiddenException` ;
  3. `adminIsAlwaysAllowed` — carol (admin) sur le tableau d'alice → pas d'exception ;
  4. (extension) `columnAccessWalksUpToTheBoardOwner` — `requireColumnAccess` remonte au tableau via un `BoardRepository` en mémoire ;
  5. (extension) `orphanColumnIsDeniedEvenToItsWouldBeOwner` — colonne dont le tableau n'existe plus → refus, même pour alice.

Aucune dépendance ajoutée : JUnit 5, surefire et `resteasy-core` (test) étaient déjà dans `pom.xml`. Pas de Mockito : les repositories factices sont des `java.lang.reflect.Proxy` qui ne répondent qu'à `findById` et échouent bruyamment sur tout autre appel.

## Exécution

`mvn test` n'est pas exécutable dans cette session (Maven Central bloqué, voir `PROGRESS.md`). Les tests ont été compilés et exécutés avec `javac` + JUnit Platform 1.9.1 / Jupiter 5.10 (paquets Ubuntu), contre des stubs d'API Jakarta (`ForbiddenException`, `Response`…) qui reproduisent les signatures réelles. Résultat : **5/5 verts** pour `BoardAccessTest` (9/9 avec `MeResourceTest`). La sortie brute est dans `TEST_REPORT.md`.

Dans le Dev Container, `cd backend && mvn test` doit donner `Tests run: 9, Failures: 0` (davantage après l'exercice 17).

## Pourquoi une sous-classe est un *stub* et non un *mock*

`StubCurrentUser` renvoie des réponses fixées d'avance (« je suis bob, pas admin ») et c'est tout. On vérifie l'**état observable** de l'objet testé (exception ou pas). Un *mock* enregistre en plus les interactions (« `isAdmin()` a-t-il été appelé une fois ? ») et le test porte sur ces appels. Ici, on ne fait aucune vérification d'interaction, juste des valeurs en conserve : c'est un stub. Il est possible parce que `CurrentUser` est une classe non finale à méthodes publiques, et que `BoardAccess` reçoit ses collaborateurs par des champs package-private (`@Inject CurrentUser currentUser;`) qu'un test du même paquet peut affecter.

## Débriefing : quels tests auraient attrapé la régression ?

Plutôt que de raisonner, j'ai **muté** la condition de `requireBoardAccess` sur une copie et relancé les tests :

| Mutation de `if (!isAdmin() && !name().equals(owner))` | Tests en échec |
|---|---|
| suppression du test admin : `if (!name().equals(owner))` | `adminIsAlwaysAllowed` |
| égalité inversée : `if (!isAdmin() && name().equals(owner))` | `ownerIsAllowed`, `otherNonAdminUserIsForbidden`, `columnAccessWalksUpToTheBoardOwner` |
| `||` au lieu de `&&` | `ownerIsAllowed`, `adminIsAlwaysAllowed`, `columnAccessWalksUpToTheBoardOwner` |

Chaque mutation fait échouer au moins un test. Le test **admin** est le seul à protéger contre la suppression du contournement admin ; les tests **propriétaire** et **refusé** couvrent ensemble l'inversion de l'égalité. Aucun des trois tests de base n'est redondant.
