# 04 — Inspect HTML and CSS

> **Conditions.** L'inspecteur n'a pas pu être utilisé sur la liste des tableaux : sans Keycloak, `authGuard` ne laisse jamais afficher la route (exercice 05, scénario D, observé). Les réponses s'appuient sur les templates et feuilles de style ; les mesures du *box model* sont calculées à partir des règles CSS et sont à confirmer dans l'onglet *Computed*.

## 1. Élément inspecté : le bouton « Delete » d'une ligne

| Observation | Réponse |
|---|---|
| Élément | `<button>` |
| Texte | `Delete` |
| Attributs importants | `class="danger"`, `type="button"` (empêche de soumettre un formulaire), plus un attribut généré `_ngcontent-xxx-cN` (encapsulation des styles Angular) |
| Parent | `<div class="board-row">` (dans `<li class="board">`, dans `<ul class="board-list">`) |
| Propriété d'accessibilité | rôle implicite `button`, nom accessible = son texte « Delete ». Il ne dit pas *quel* tableau est supprimé : un `aria-label="Delete board Sprint 1"` serait meilleur |

Source : `board-list.component.html:35`.

## 2. Box model (`button.danger`)

D'après `board-list.component.css:20-28` et `:40-43` :
- **content** : largeur du texte « Delete » (≈ 45 px à 16 px de police système), hauteur d'une ligne ;
- **padding** : `0.55rem 0.9rem` → 8,8 px haut/bas, 14,4 px gauche/droite ;
- **border** : `none` → 0 ;
- **margin** : 0 (aucune règle) ; l'espacement vient du `gap: 0.75rem` du parent flex `.board-row`.

Modifier temporairement le padding à `2rem` agrandit le bouton et pousse les voisins, mais la ligne reste alignée (`align-items: center`).

## 3. Expériences CSS

Changer `color`, `gap`, ou décocher `background` dans le panneau *Styles* s'applique instantanément. **Après rechargement, tout disparaît**, car DevTools modifie le CSSOM de *cette page en mémoire*. Rien n'est écrit dans `board-list.component.css` ; au rechargement, le navigateur retélécharge le bundle compilé par Angular depuis les fichiers source.

## 4. Source Angular

| Question | Réponse |
|---|---|
| Template | `frontend/src/app/boards/board-list.component.html` |
| Feuille de style | `frontend/src/app/boards/board-list.component.css` (déclarée par `styleUrl`, `board-list.component.ts:17`) |
| Sélecteur | `button.danger` (couleur `#b91c1c`, fond transparent) qui surcharge `button` (fond bleu) |
| Global ou scopé ? | **Scopé au composant** : Angular réécrit `button.danger` en `button.danger[_ngcontent-xxx]` (encapsulation `Emulated` par défaut). Seul `src/styles.css` est global (`box-sizing`, `body`) |

## Bilan

- **HTML** = structure et sens (un bouton, une liste, un lien) ; **CSS** = présentation (couleur, espacement, disposition).
- **DOM vs template :** le template est compilé en instructions JS qui *créent* le DOM ; le DOM inspecté contient en plus les attributs `_ngcontent`/`_nghost` et les commentaires de blocs `@if`/`@for`, mais pas la syntaxe `@for`/`{{ }}` elle-même.
- Une propriété visible : la couleur rouge du bouton → `color: #b91c1c` dans `button.danger`.
- Une modification DevTools est temporaire : elle ne touche que la page en mémoire.

## Extensions

- **Flexbox :** `.board-row` (`display: flex`) a un axe principal **horizontal** (`flex-direction` par défaut `row`) et un axe secondaire vertical (`align-items: center`). `.board-name` a `flex: 1` et absorbe l'espace libre, ce qui pousse méta et bouton à droite.
- Nom accessible du bouton : « Delete » (cf. remarque ci-dessus).
