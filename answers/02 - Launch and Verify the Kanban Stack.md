# 02 — Launch and Verify the Kanban Stack

> **Conditions.** Dans cette session, seul le frontend a pu être lancé (`ng serve`, observé). PostgreSQL et Keycloak ne démarrent pas (images Docker refusées par la politique réseau), et Liberty ne peut pas être construit (Maven Central refusé). Le détail des tentatives est dans `PROGRESS.md`.

## 3. Vérification de chaque partie

| Partie | Preuve attendue | Résultat dans cette session |
|---|---|---|
| Angular | L'application se charge sur 4200 | ✅ **observé** : `ng serve` répond `200` sur `/` et compile le bundle (`Application bundle generation complete`) |
| Jakarta EE | `/health/ready` renvoie UP | ❌ non vérifiable ; via le proxy Angular, **observé** `500` + `ECONNREFUSED 127.0.0.1:9080` (backend absent) |
| PostgreSQL | check `kanban-database` UP | ❌ non vérifiable (image `postgres:16` refusée) |
| Keycloak | connexion sur 8081 | ❌ non vérifiable ; **observé** `ERR_CONNECTION_REFUSED` sur `localhost:8081` |
| Bout en bout | la liste (vide) s'affiche après connexion | ❌ non vérifiable |

Procédure à suivre dans le Dev Container : `cd backend && mvn liberty:dev` (terminal 1, déjà lancé à l'exercice 01), `cd frontend && npm start` (terminal 2), puis `http://localhost:4200` → connexion `alice`/`alice`.

## 4. Où tourne chaque élément

| Élément | Conteneur, processus ou page ? |
|---|---|
| PostgreSQL | **Conteneur** `kanban-postgres` (service `postgres` de `docker-compose.yml`, démarré par `runServices`, `devcontainer.json:14`) |
| Keycloak | **Conteneur** `kanban-keycloak` (idem) |
| `mvn liberty:dev` | **Processus** dans le conteneur `dev` (le Dev Container) |
| `npm start` | **Processus** dans le conteneur `dev` (`ng serve --host 0.0.0.0`, `package.json:9`) |
| Interface Angular | **Page** dans le navigateur de l'hôte (le JS s'exécute dans le navigateur, pas dans le conteneur) |
| Écran de connexion Keycloak | **Page** dans le navigateur, servie par le conteneur Keycloak via `localhost:8081` |

## Bilan

- **Démarrés automatiquement :** PostgreSQL et Keycloak (`"runServices": ["postgres", "keycloak"]`), avec le conteneur `dev` lui-même.
- **Les deux commandes manuelles :** `mvn liberty:dev` et `npm start`.

## Échecs rencontrés (méthode « If Setup Fails »)

| # | Étape | Message exact | Commande | Où | Hypothèse (confirmée) |
|---|---|---|---|---|---|
| 1 | Démarrer PostgreSQL/Keycloak | `failed to resolve reference "quay.io/keycloak/keycloak:26.0": ... Forbidden` | `docker compose up -d postgres keycloak` | hôte de la session | le proxy sortant refuse `quay.io` et `registry-1.docker.io` (statut du proxy : `connect_rejected ... 403`) |
| 2 | Construire le backend | `gateway answered 403 to CONNECT` pour `repo.maven.apache.org:443` | `curl https://repo.maven.apache.org/maven2/` | hôte de la session | même politique pour Maven Central |

Ce n'est pas un bug du projet, et réinstaller les outils n'y changerait rien : c'est exactement ce que la méthode demandait de distinguer.
