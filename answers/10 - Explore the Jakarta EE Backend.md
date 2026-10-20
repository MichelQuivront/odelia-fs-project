# 10 — Explore the Jakarta EE Backend

> **Conditions.** Liberty ne peut pas être construit dans cette session (Maven Central bloqué, voir `PROGRESS.md`). Les parties 1, 2 et 4 viennent de la lecture des fichiers. Les statuts de la partie 3 sont ceux attendus d'après la configuration et les spécifications ; ils sont **à confirmer** dans le Dev Container.

## 1. Configuration d'exécution

| Question | Réponse | Source |
|---|---|---|
| Version de Java | 21 | `pom.xml:14` (`maven.compiler.release`) ; Dev Container `devcontainer.json:18` |
| Profil / version Jakarta EE | Jakarta EE 11 **Web Profile** | `pom.xml:31-34` (`jakarta.jakartaee-web-api` 11.0.0, `provided`) ; `server.xml:7` (`webProfile-11.0`) |
| Version MicroProfile | 7.1 (+ `mpMetrics-5.1` à part) | `pom.xml:38-44` ; `server.xml:9,13` |
| Activation de CDI | `src/main/webapp/WEB-INF/beans.xml`, `bean-discovery-mode="all"` | `beans.xml:7` |
| Nom JNDI de la datasource | `jdbc/kanban` | `server.xml:39` ; repris par `@Repository(dataStore = "jdbc/kanban")` et `@Resource(lookup = "jdbc/kanban")` |
| Source de la config de base | variables Liberty `db.host/port/name/user/password` (`server.xml:21-25`), surchargées par les variables d'environnement `DB_HOST`… (`docker-compose.yml:44-49`, `devcontainer.json:41-43`) | |
| Fichier de l'issuer JWT | `src/main/resources/META-INF/microprofile-config.properties` (`mp.jwt.verify.issuer`, ligne 17) | |

## 2. Point d'entrée de l'application (`KanbanApplication.java`)

1. **Chemin de base :** `/api` (`@ApplicationPath("/api")`, ligne 25).
2. **Méthode d'authentification :** `MP-JWT`, jeton bearer (`@LoginConfig(authMethod = "MP-JWT", realmName = "kanban")`, ligne 26).
3. **Classe mère :** `jakarta.ws.rs.core.Application`.
4. **URL dans l'application sécurisée :** tout ce qui est sous `/api/*`, donc `/api/boards…`, `/api/lists…`, `/api/cards…`. `/health`, `/openapi` et `/metrics` sont servis par des fonctionnalités Liberty, **hors** de cette application JAX-RS.

## 3. Le backend en fonctionnement (attendu)

| Endpoint | Statut | Représentation | Rôle |
|---|---:|---|---|
| `/health/ready` | 200 (503 si la base tombe) | JSON MicroProfile Health | sonde de disponibilité (check `kanban-database`) |
| `/openapi` | 200 | YAML OpenAPI 3 (JSON sur demande) | contrat de l'API, généré depuis les annotations |
| `/openapi/ui` | 200 | HTML (Swagger UI) | exploration interactive, bouton *Authorize* grâce à `@SecurityScheme` |
| `/metrics` | 200 | texte Prometheus / OpenMetrics | métriques JVM et JAX-RS ; ouvert sans jeton (`<mpMetrics authentication="false"/>`, `server.xml:66`) |

Aucun ne demande de jeton. `/api/boards` sans jeton renverrait `401`.

## 4. Responsabilités

| Artefact | Catégorie |
|---|---|
| `pom.xml` | **Dépendances** (et build : WAR, plugin Liberty, surefire) |
| `server.xml` | **Configuration d'exécution** (Liberty : features, ports, datasource, CORS) |
| `beans.xml` | **Configuration applicative** (activation et découverte CDI dans le WAR) |
| `microprofile-config.properties` | **Configuration applicative** (portable : MP-JWT) |
| `KanbanApplication.java` | **Code Java** (active JAX-RS, `/api`, MP-JWT, métadonnées OpenAPI) |
| `DatabaseReadinessCheck.java` | **Code Java** (check `@Readiness` CDI) |

## Comment une classe Java devient joignable par une URL

1. `mvn package` produit `kanban-backend.war`, que Liberty déploie à la racine (`server.xml:71`, `contextRoot="/"`).
2. La feature `webProfile-11.0` démarre JAX-RS ; Liberty trouve la sous-classe d'`Application` annotée `@ApplicationPath("/api")`.
3. Il scanne les classes `@Path` (ex. `BoardResource`, `@Path("/boards")`) et les instancie comme beans CDI `@RequestScoped`, avec injection (`@Inject`) des repositories générés par Jakarta Data.
4. Une requête `GET /api/boards/3` est routée par concaténation : contexte `/` + `/api` + `/boards` + `/{id}` → `BoardResource.getBoard(3)`. Avant d'atteindre la méthode, elle traverse MP-JWT (validation du jeton) puis `@RolesAllowed`.
