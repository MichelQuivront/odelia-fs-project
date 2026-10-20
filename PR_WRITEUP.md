# Exercise 17 — Board sharing (`BoardMember`): write-up

## Owner-only vs. any-collaborator actions in `BoardAccess`

`BoardAccess` now has two checks, and every endpoint picks exactly one of them, so the rule lives in a single class:

- **`requireBoardAccess(board)`, the collaborator level.** It passes for an admin, for the owner (`currentUser.name()` equals `board.getOwner()`), or for a member (`BoardMemberRepository.existsByBoardIdAndUsername`). Reading a board, its columns, its cards and its member list goes through it, and so does creating, editing, moving or deleting columns and cards. `requireColumnAccess` and `requireCardAccess` still walk up to the board and then call this check, so `BoardListResource` and `CardResource` did not change: a member got R7 for free.
- **`requireBoardOwnership(board)`, the owner-only level.** It passes only for the owner or an admin. `BoardResource` uses it, through an `ownedBoard(id)` helper, for renaming, deleting and the three membership endpoints.

The owner is never stored as a `BoardMember` row. `Board.owner` already answers that question, so adding or removing the owner is a 400 (R5/R10). A second copy of ownership could only go stale. Membership is read from the database on every request, which is why a removed member is refused on their very next call; there is no cache to invalidate.

**403 before 400.** Owner-only endpoints authorize *before* they validate. `@Valid` runs before the method body, so `updateBoard` and `addMember` validate by hand, the former through the injected Bean Validation `Validator` so the `Board` constraints are not duplicated. A member who sends a blank name or a blank username gets 403 and learns nothing from a 400. This is covered by `BoardResourceTest.memberGets403NotA400OnEveryOwnerOnlyAction` and by `scripts/test-sharing.sh`. One limit remains: a body that is not JSON at all is rejected by the JAX-RS runtime with 400 before any resource code runs.

## Edge case: a member trying to remove someone, including themselves

`DELETE /api/boards/{id}/members/{username}` is owner-only (R4), so a member is refused with **403** whether they target another member or themselves. A self-service "leave this board" would be a reasonable feature, but R4 reserves the endpoint to the owner, and allowing self-removal would mean branching on the target inside the resource, which is exactly the kind of scattered rule `BoardAccess` exists to prevent. Both cases are tested (`memberCannotRemoveAnotherMember`, and the `bob removes himself -> 403` check). The membership list is asserted unchanged afterwards.

Two related cases are handled the same way:
- usernames are trimmed and lower-cased before use (`" Bob "` → `bob`), so `BOB` cannot duplicate `bob`, and `DELETE …/members/BOB` removes him, because Keycloak issues `preferred_username` in lower case;
- `GET /api/boards` merges owned and shared boards in a `LinkedHashMap` keyed by id, so a board is never listed twice, even if a stray row made someone a member of their own board.

Deleting a board deletes its memberships in the same transaction, like columns and cards.

*Not done, out of scope:* the backend does not check that a username exists in Keycloak before adding it. An unknown name is a harmless dangling row that grants nothing until such a user signs in.
