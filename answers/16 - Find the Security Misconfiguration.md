# 16 — Find the Security Misconfiguration

## Constat préalable : les vrais fichiers sont sains

| Snippet | Fichier réel | Valeur réelle (vérifiée) | Faille présente ? |
|---|---|---|---|
| A | `server.xml:49-55` | `allowedOrigins="http://localhost:4200"` | non |
| B | `microprofile-config.properties:17` | `mp.jwt.verify.issuer=http://localhost:8081/realms/kanban` | non |
| C | `backend/src/main/java/**` | seul mapper : `ForbiddenExceptionMapper` (`ExceptionMapper<ForbiddenException>`) | non |
| D | `docker-compose.yml`, `.devcontainer/docker-compose.yml` | aucune variable `*_TOKEN` / secret ; `git grep sk_live $(git rev-list --all)` ne le trouve que dans `exercises/16…` et sa solution | non |

**Aucun fichier de sécurité n'a donc été modifié** (règle 5 du `CLAUDE.md`) : l'exercice demande de corriger les extraits, et les fichiers réels correspondent déjà à la version corrigée. La section « Preuves » donne les requêtes qui démontrent que la configuration réelle refuse ce que les extraits accepteraient.

## Snippet A — CORS `allowedOrigins="*"` + `allowCredentials="true"`

- **OWASP :** A05:2021 *Security Misconfiguration* (CORS permissif).
- **Risque concret :** la spécification CORS interdit `Access-Control-Allow-Origin: *` avec des credentials. Selon l'implémentation, ce snippet échoue donc de façon déroutante (le navigateur refuse la réponse), ou bien, cas dangereux, le serveur ou un proxy **renvoie l'`Origin` de l'appelant en écho**. Résultat : n'importe quel site (`https://evil.example`) que visite un utilisateur peut émettre des requêtes cross-origin *avec credentials* vers `localhost:9080` et **lire les réponses**. Dans cette application, l'authentification passe par un jeton bearer gardé en mémoire par keycloak-js, pas par un cookie : le site malveillant n'a pas le jeton, ce qui limite l'impact aujourd'hui. Mais la protection du navigateur est désactivée pour toute l'API, et la faille devient exploitable dès qu'un cookie de session existe (LTPA de Liberty, cookie MP-JWT) ou qu'un jeton fuit vers une page tierce.
- **Correction en une ligne :** `allowedOrigins="http://localhost:4200"` (liste explicite des origines du frontend ; en production, l'origine publique).

## Snippet B — issuer `http://keycloak:8080/realms/kanban`

- **OWASP :** A07:2021 *Identification and Authentication Failures* (validation de jeton mal configurée ; aussi A05).
- **Risque concret :** Keycloak inscrit dans `iss` l'URL *par laquelle le client l'a contacté*. Le navigateur passe par `localhost:8081`, donc **tous les jetons légitimes** ont `iss=http://localhost:8081/realms/kanban` et sont refusés : **401 pour tout le monde**, l'application est inutilisable. À l'inverse, seuls seraient acceptés les jetons obtenus par l'URL *interne* au réseau Docker, c'est-à-dire par un composant qui n'est pas le frontend prévu. On fait confiance au mauvais émetteur. Les clés étant celles du realm, cela ne permet pas de forger un jeton, mais la vérification de l'émetteur, qui sert à rattacher un jeton à *ce* fournisseur et à *ce* canal, devient incohérente.
- **Correction en une ligne :** `mp.jwt.verify.issuer=http://localhost:8081/realms/kanban`.

## Snippet C — mapper générique qui renvoie la stack trace

- **OWASP :** A05:2021 *Security Misconfiguration* (gestion d'erreurs verbeuse, CWE-209 : *Information Exposure Through an Error Message*).
- **Risque concret :**
  1. **Fuite d'information :** chaque erreur renvoie au client noms de classes (`com.odelia.kanban…`), versions de bibliothèques (EclipseLink, PostgreSQL JDBC), chemins de fichiers et parfois du SQL avec des valeurs. C'est une carte pour un attaquant.
  2. **Mauvais statuts :** `ExceptionMapper<Exception>` s'applique aussi aux `WebApplicationException` sans mapper plus spécifique. Le `404` de `notFound()` (`BoardResource.java:157-159`) et le `400` de validation deviendraient des **`500` avec stack trace**.
- **Correction en une ligne :** ne pas renvoyer la trace, mais `Map.of("error", "Internal server error")` en la journalisant côté serveur. Ou plus simplement : supprimer ce mapper (le projet n'en a pas).

## Snippet D — secret en clair dans `docker-compose.yml`

- **OWASP :** A07:2021 *Identification and Authentication Failures* (CWE-798, identifiants codés en dur ; souvent rangé aussi sous A05 / A02).
- **Risque concret :** le fichier est versionné. Toute personne ayant lu le dépôt (fork, CI, ancien collaborateur) possède une clé `sk_live_` (préfixe de production) qui donne des droits admin. Elle est aussi visible via `docker inspect` et `/proc/<pid>/environ`. Retirer la ligne ne suffit pas : elle reste dans l'historique Git, donc il faut **révoquer et faire tourner** la clé.
- **Correction en une ligne :** `ADMIN_API_TOKEN: ${ADMIN_API_TOKEN:?set it in .env}`, valeur dans un `.env` ignoré par Git (ou un Docker/Kubernetes secret). Les `DB_PASSWORD: kanban` réels sont des valeurs par défaut de développement assumées par le cours, pas des secrets de production.

## Débriefing : pourquoi l'issuer doit rester `localhost:8081` alors que les clés viennent de `keycloak:8080`

Ce sont deux questions différentes :
- `mp.jwt.verify.publickey.location` répond à « **où** le backend va-t-il *chercher* les clés ? ». C'est un appel réseau serveur à serveur, qui doit utiliser l'adresse joignable depuis le conteneur (`keycloak:8080`).
- `mp.jwt.verify.issuer` répond à « **qui** doit avoir *émis* ce jeton ? ». C'est une comparaison de chaîne avec le claim `iss`, écrit par Keycloak selon l'URL publique utilisée par le navigateur (`localhost:8081`).

Une signature valide prouve seulement qu'*un* realm de ce serveur Keycloak a émis le jeton. L'issuer prouve que c'est **le realm `kanban`, par son URL publique**. Sur un serveur multi-realm, c'est lui qui empêcherait un jeton correctement signé par un autre realm d'être accepté ici. Aligner l'issuer sur l'URL des clés « par commodité » casse cette garantie, même si, dans cette démo à un seul realm, l'erreur se manifeste par un refus général (401).

Les deux extraits A et B relèvent de la même erreur : faire confiance à la mauvaise origine. A fait confiance à *toutes* les origines web ; B fait confiance à l'émetteur *interne* au lieu de l'émetteur public par lequel les utilisateurs se connectent.

## Extension : C contre `ForbiddenExceptionMapper`

JAX-RS choisit le mapper dont le type générique est **le plus proche** de la classe de l'exception levée dans sa hiérarchie (Jakarta REST, §4.4). Pour une `ForbiddenException`, `ExceptionMapper<ForbiddenException>` (distance 0) l'emporte sur `ExceptionMapper<Exception>` (distance 4) : les refus d'accès gardent leur `403` JSON. Le snippet C neutralise pourtant l'**intention** du projet :
- toutes les autres `WebApplicationException` (`404` de `notFound()`, `400`, `NotAuthorizedException`) n'ont pas de mapper spécifique, et tombent dans C en `500` avec stack trace ;
- `ForbiddenExceptionMapper` existe pour qu'une erreur *attendue* ne soit pas traitée comme une erreur *inattendue* par le mapper attrape-tout de `mpMetrics` (avertissement `CWPMI2006W`). Un second attrape-tout applicatif efface cette distinction pour tous les autres cas : chaque 404 ressemble à un bug serveur, et les vrais bugs sont noyés dans la masse.

## Preuves sur la configuration réelle (à exécuter dans le Dev Container)

Non exécutables dans cette session (pas de Liberty ni de Keycloak, voir `PROGRESS.md`).

```bash
# A — origine étrangère : aucun Access-Control-Allow-Origin ; origine du frontend : autorisée
curl -si -X OPTIONS http://localhost:9080/api/boards -H 'Origin: https://evil.example' \
     -H 'Access-Control-Request-Method: GET' | grep -i '^access-control-allow-origin' || echo "refusé (attendu)"
curl -si -X OPTIONS http://localhost:9080/api/boards -H 'Origin: http://localhost:4200' \
     -H 'Access-Control-Request-Method: GET' | grep -i '^access-control-allow-origin'   # → http://localhost:4200

# B — jeton à l'issuer interne : 401 ; jeton à l'issuer public : 200
INTERNAL=$(KC_URL=http://keycloak:8080 bash scripts/token.sh alice)   # depuis le Dev Container
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $INTERNAL" http://localhost:9080/api/boards  # 401
PUBLIC=$(bash scripts/token.sh alice)                                   # depuis l'hôte (localhost:8081)
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $PUBLIC"   http://localhost:9080/api/boards  # 200

# C — un 404 reste un 404 JSON-less, sans stack trace
curl -si -H "Authorization: Bearer $PUBLIC" http://localhost:9080/api/boards/999999 | head -1   # 404
```
