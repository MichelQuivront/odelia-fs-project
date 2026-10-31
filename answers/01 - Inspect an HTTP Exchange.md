# 01 — Inspect an HTTP Exchange

> **Conditions.** Dans cette session, Liberty ne peut pas démarrer : Maven Central, Docker Hub et quay.io sont bloqués par la politique réseau (voir `PROGRESS.md`). Les valeurs ci-dessous sont **déduites du code et des spécifications**, sauf mention « observé ». Les lignes marquées « à confirmer » doivent être relevées dans le Dev Container.

## Tableau d'observation (`GET http://localhost:9080/health/ready`)

| Observation | Réponse | Source |
|---|---|---|
| Méthode HTTP | `GET` (navigation d'une adresse dans la barre d'URL) | — |
| URL complète | `http://localhost:9080/health/ready` | énoncé |
| Schéma | `http` (pas de TLS en dev ; Liberty ouvre aussi `https` sur 9443) | `server.xml:27-30` |
| Hôte | `localhost` (port transféré du Dev Container, `devcontainer.json:31`) | |
| Port | `9080` | `server.xml:16`, `pom.xml:20` |
| Chemin | `/health/ready` (exposé par MicroProfile Health, hors de `/api`) | `DatabaseReadinessCheck.java:16` |
| Statut | `200 OK` si la base répond, `503 Service Unavailable` si un check est DOWN | spec MP Health |
| Content-Type | `application/json` | spec MP Health |
| Corps | `{"status":"UP","checks":[{"name":"kanban-database","status":"UP"}]}` | `DatabaseReadinessCheck.java:26-29` |
| Durée | à confirmer (quelques ms ; une ouverture de connexion JDBC + `isValid(2)`) | |

## Interprétation

1. **Qui initie ?** Le navigateur (le client). Le serveur ne fait que répondre.
2. **Quel processus reçoit ?** Le serveur OpenLiberty `kanbanServer` lancé par `mvn liberty:dev` (`pom.xml:99`), qui écoute sur 9080. La requête passe par la redirection de port du Dev Container.
3. **Le statut.** `200` signifie que tous les checks `@Readiness` ont répondu UP. MicroProfile Health renvoie `503` dès qu'un check est DOWN, c'est ce qui permet à un orchestrateur de ne pas router de trafic.
4. **Preuve que c'est du JSON.** L'en-tête `Content-Type: application/json` (la seule preuve normative), et le panneau *Preview/Response* qui l'affiche en arbre.
5. **200 ≠ tout fonctionne.** Le check ne teste que la connexion PostgreSQL (`connection.isValid(2)`). Il ne dit rien de Keycloak (les clés publiques sont chargées paresseusement, `docker-compose.yml:40-41`), ni de la validité des jetons, ni du frontend, ni de la logique métier. Exemple observé dans cette session (exercice 05) : quand Keycloak est arrêté, l'application est inutilisable alors qu'un `/health/ready` sur un backend sain resterait `200`.

## Navigateur vs ligne de commande

`curl -i http://localhost:9080/health/ready` montre la ligne de statut, les en-têtes bruts et le corps.

- **Commun aux deux :** statut, en-têtes de réponse, corps.
- **Présenté différemment :** DevTools affiche aussi les en-têtes de requête, le temps (*Timing*), l'initiateur, et met le JSON en forme ; `curl -i` ne montre que la réponse, en texte brut (`-v` pour la requête).
- **Pour un script :** `curl` (sortie texte, code de sortie, `-w '%{http_code}'`, `--fail`), utilisable dans un script ou une sonde Docker.

## Extension : `/openapi`

`/openapi` renvoie un document **OpenAPI 3 en YAML** par défaut (`Content-Type: application/yaml`, ou JSON avec `Accept: application/json` / `?format=JSON`). Il est généré par MicroProfile OpenAPI à partir des annotations JAX-RS et de `@OpenAPIDefinition`/`@SecurityScheme` (`KanbanApplication.java:25-34`). C'est une **description de l'API**, pas un état du service : il ne contacte pas la base et répond toujours `200`.
