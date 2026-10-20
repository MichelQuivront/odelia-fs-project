# 06 — Explore the Angular Application

> **Conditions.** L'application n'est pas utilisable connectée dans cette session (Keycloak indisponible, cf. exercice 05). La partie 1 est donc décrite à partir des templates ; les parties 2 à 4 reposent sur la lecture du code.

## 1. Application en fonctionnement

- **Coquille :** `<header class="app-header">` (titre « Kanban », slogan, nom d'utilisateur, badge admin, *Sign out*) + `<main><router-outlet /></main>` — `app.component.html`.
- **Route liste :** `/` → `BoardListComponent`.
- **Route détail :** `/boards/:id` → `BoardDetailComponent`.
- **Nom d'utilisateur :** `auth.username()`, signal alimenté par le claim `preferred_username`.
- **États :** chargement « Loading boards… », vide « No board yet… », erreur `<p class="error">` (`board-list.component.html:13-20`).

## 2. Démarrage

| Question | Réponse |
|---|---|
| Fonction qui démarre Angular | `bootstrapApplication` — `main.ts:5` |
| Composant racine | `AppComponent` |
| Objet de configuration | `appConfig` (`app.config.ts:9`) |
| Routage enregistré | `provideRouter(routes)` — `app.config.ts:12`, routes dans `app.routes.ts:7-11` |
| `HttpClient` enregistré | `provideHttpClient(withFetch(), withInterceptors([authInterceptor]))` — `app.config.ts:13` |
| Initialisation de l'authentification | `provideAppInitializer(() => inject(AuthService).init())` — `app.config.ts:16` |

## 3. Comportement visible → source

| Comportement | Fichier | Classe / identifiant |
|---|---|---|
| En-tête et *Sign out* | `app.component.html` / `.ts` | `AppComponent`, `auth.logout()` |
| Liste des tableaux | `boards/board-list.component.*` | `BoardListComponent` |
| Détail | `boards/board-detail.component.*` | `BoardDetailComponent` |
| Routes | `app.routes.ts` | `routes` |
| Opérations HTTP | `services/board.service.ts` | `BoardService` |
| État d'authentification | `auth/auth.service.ts` | `AuthService` (`authenticated`, `username`, `roles`, `isAdmin`) |

## 4. Types du domaine (`models/board.ts`)

1. Trois interfaces : `Board`, `BoardList`, `Card`.
2. Propriété optionnelle : `id?`, `owner?`, `createdAt?` de `Board` ; `description?` de `Card`.
3. Liaison par identifiant : `BoardList.boardId` (vers `Board.id`) et `Card.listId` (vers `BoardList.id`). C'est le miroir des colonnes `BOARD_ID`/`LIST_ID` du backend.
4. **Pas de validation à l'exécution :** une `interface` TypeScript est effacée à la compilation. `http.get<Board[]>()` n'est qu'une *assertion de type* : si le serveur renvoie autre chose, rien ne le détecte avant qu'une propriété manquante produise `undefined`. Il faudrait un validateur (zod, contrôle manuel) pour une vraie garantie.

## Chemin de démarrage

```text
main.ts  bootstrapApplication(AppComponent, appConfig)
  -> app.config.ts  provideAppInitializer → AuthService.init() (Keycloak check-sso)
  -> AppComponent   rend l'en-tête + <router-outlet>
  -> Router         '' → authGuard (authenticated() ?) → BoardListComponent.ngOnInit → BoardService.getBoards()
board-list template  (@if loading / @else if vide / @for boards)
```

## Extension : types TypeScript

| Type | Emplacement |
|---|---|
| `Record` | `cardsByList = signal<Record<number, Card[]>>({})` — `board-detail.component.ts:47` |
| Union avec `null` | `signal<string \| null>(null)` (`error`) — `board-list.component.ts:24` |
| Tableau | `signal<Board[]>([])` — `board-list.component.ts:22` |
| Propriété optionnelle | `description?: string` — `models/board.ts:22` |
