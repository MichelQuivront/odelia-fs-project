# 08 — Observe Angular Authentication

> **Conditions.** Keycloak est indisponible dans cette session, donc pas de connexion réelle. Les requêtes d'initialisation **ont** été observées (Chromium + Playwright, voir exercice 05). Aucun jeton n'est reproduit ici.

## 1. Initialisation

| Réglage | Valeur | Source |
|---|---|---|
| URL Keycloak | `http://localhost:8081` | `environment.ts:11` |
| Realm | `kanban` | `environment.ts:12` |
| Client | `kanban-app` | `environment.ts:13` |
| `onLoad` | `check-sso` | `auth.service.ts:35` |
| PKCE | `S256` | `auth.service.ts:36` (observé : `code_challenge_method=S256` dans l'URL `/auth`) |

`AuthService.init()` est attendu par `provideAppInitializer` (`app.config.ts:16`) : Angular n'affiche rien tant que la promesse n'est pas résolue.

**`check-sso` vs `login-required` :** `check-sso` demande seulement « une session existe-t-elle ? » (`prompt=none`, observé dans l'URL) et revient dans tous les cas, sans montrer d'écran de connexion. `login-required` enverrait d'emblée sur la page de connexion. Ici, c'est le **guard** qui décide de forcer la connexion, route par route.

## 2. Le guard

Scénario : déconnexion, puis ouverture directe de `/boards/3`. `authGuard` voit `authenticated() === false` et appelle `auth.login(window.location.origin + state.url)`. **Ligne qui conserve l'URL demandée : `auth.guard.ts:20`**. `state.url` (`/boards/3`) devient le `redirect_uri` de Keycloak ; après connexion, keycloak-js revient sur `/boards/3`.

Observé (sans Keycloak) : l'URL d'autorisation contient bien `redirect_uri=http%3A%2F%2F127.0.0.1%3A4200%2Fboards%2F3`. Cette première redirection vient toutefois de `check-sso`, avant le guard.

## 3. L'intercepteur

- Sur `GET /api/boards`, l'en-tête `Authorization: Bearer …` est ajouté (`auth.interceptor.ts:25-28`). C'est vérifié par le test unitaire existant `attaches the bearer token to API calls`, **passé** dans cette session (`npm test`, 10/10).
- Requête ne commençant pas par `/api` : les appels de keycloak-js vers `localhost:8081`, ou les fichiers statiques. La condition `if (!req.url.startsWith(environment.apiUrl)) return next(req)` (ligne 20) les laisse passer intacts, ce que vérifie aussi le test `leaves calls to other hosts alone`.
- **Pourquoi pas partout :** le jeton est un *bearer token* ; quiconque le détient agit comme l'utilisateur pendant sa durée de vie (5 min ici). L'envoyer à un CDN, un service d'analytics ou une API tierce le ferait fuiter.

## 4. Expérience utilisateur vs sécurité

1. **Contourner le guard ?** Oui. Tout le code tourne dans le navigateur de l'utilisateur, qui peut le modifier (DevTools, proxy, build local).
2. **Accès au tableau d'un autre ?** Non. Sans jeton valide, l'API répond `401` ; avec son propre jeton, `BoardAccess.requireBoardAccess` répond `403` sur le tableau d'autrui (`BoardAccess.java:38-42`).
3. **Mécanismes backend indispensables :** validation du JWT par MP-JWT (signature JWKS, `iss`, `aud`, expiration — `microprofile-config.properties`, `@LoginConfig`), `@RolesAllowed` sur chaque ressource, contrôle d'appartenance dans `BoardAccess`, owner tiré du jeton et non du JSON (`BoardResource.java:96`).
4. **Masquer un bouton n'est pas une autorisation :** la requête HTTP reste faisable avec `curl` ou depuis la console. Seul le serveur fait respecter la règle ; l'interface ne fait qu'éviter des clics inutiles.

## Chaîne

```text
app initializer (provideAppInitializer)
  -> AuthService.init()       keycloak-js check-sso, PKCE S256, signaux authenticated/username/roles
  -> authGuard                authenticated() ? true : login(origin + state.url)
  -> Keycloak redirect/return code d'autorisation → échange PKCE → jetons
  -> authInterceptor          Authorization: Bearer <token> sur /api uniquement, refresh à <30 s
  -> backend validation       MP-JWT (iss, aud, signature, exp) → @RolesAllowed → BoardAccess
```

## Extension : noms des claims (sans valeurs)

Émetteur : `iss` ; audience : `aud` (contient `kanban-app` grâce au mapper d'audience) ; utilisateur : `preferred_username` (et `sub`, `upn`) ; rôles : `realm_access.roles` (lu par le frontend, `auth.service.ts:83`) et `groups` (lu par MP-JWT, ajouté par le mapper « realm roles as groups », `keycloak/README.md`).
