#!/usr/bin/env bash
# =============================================================================
# Exercise 17 - Board Sharing (BoardMember) - applies the full implementation.
#
# Run from the repository root (the folder containing backend/ and frontend/),
# ideally inside the Dev Container:   bash apply-exercise17.sh
# Options:  --skip-build   only write/patch the files
#
# Idempotent: running it twice rewrites the same files and skips patches that
# are already applied.
# =============================================================================
set -euo pipefail

SKIP_BUILD=false
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=true

[[ -f backend/pom.xml && -f frontend/angular.json ]] || {
  echo "ERROR: run this script from the repository root (backend/ and frontend/ expected)." >&2
  exit 1
}

B=backend/src/main/java/com/odelia/kanban
T=backend/src/test/java/com/odelia/kanban
F=frontend/src/app

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# -----------------------------------------------------------------------------
step "Git branch"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git status --porcelain -- backend frontend)" ]]; then
    echo "ERROR: uncommitted changes in backend/ or frontend/. This script OVERWRITES several files - commit or stash first." >&2
    exit 1
  fi
  git checkout -b exercise-17-board-sharing 2>/dev/null || git checkout exercise-17-board-sharing
else
  echo "Not a git repository (ZIP download?) - skipping. Work in your fork to submit the PR."
fi

mkdir -p "$B/entity" "$B/repository" "$B/resource" "$B/security" "$T/security" scripts

# =============================================================================
step "Backend - entity/BoardMember.java"
cat > "$B/entity/BoardMember.java" <<'EOF'
package com.odelia.kanban.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalDateTime;

/**
 * A user who has MEMBER access to a board they do not own.
 *
 * <p>The owner is never stored here: {@link Board#getOwner()} already answers
 * that question. Like {@link BoardList}, the board is referenced by its id
 * rather than by a JPA association, so the repository and the JSON stay flat.</p>
 */
@Entity
@Table(name = "BOARD_MEMBER",
       uniqueConstraints = @UniqueConstraint(columnNames = { "BOARD_ID", "USERNAME" }))
public class BoardMember {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "BOARD_ID", nullable = false)
    private long boardId;

    @NotBlank
    @Size(max = 120)
    @Column(name = "USERNAME", nullable = false, length = 120)
    private String username;

    @Column(name = "CREATED_AT")
    private LocalDateTime createdAt;

    public BoardMember() {
    }

    public BoardMember(long boardId, String username) {
        this.boardId = boardId;
        this.username = username;
        this.createdAt = LocalDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public long getBoardId() {
        return boardId;
    }

    public void setBoardId(long boardId) {
        this.boardId = boardId;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
EOF

# =============================================================================
step "Backend - repository/BoardMemberRepository.java"
cat > "$B/repository/BoardMemberRepository.java" <<'EOF'
package com.odelia.kanban.repository;

import com.odelia.kanban.entity.BoardMember;
import jakarta.data.repository.CrudRepository;
import jakarta.data.repository.Repository;
import java.util.List;

/**
 * Jakarta Data repository for {@link BoardMember}. Every method is "query by
 * method name": no implementation and no JPQL.
 */
@Repository(dataStore = "jdbc/kanban")
public interface BoardMemberRepository extends CrudRepository<BoardMember, Long> {

    List<BoardMember> findByBoardIdOrderByUsernameAsc(long boardId);

    /** The memberships of one user - used to extend {@code GET /api/boards}. */
    List<BoardMember> findByUsername(String username);

    boolean existsByBoardIdAndUsername(long boardId, String username);

    long deleteByBoardIdAndUsername(long boardId, String username);

    void deleteByBoardId(long boardId);
}
EOF

# =============================================================================
step "Backend - resource/MemberCommand.java"
cat > "$B/resource/MemberCommand.java" <<'EOF'
package com.odelia.kanban.resource;

/**
 * Body of {@code POST /api/boards/{id}/members}: {@code { "username": "bob" }}.
 *
 * <p>Deliberately no Bean Validation annotations: they would run before the
 * resource method and answer 400 to a caller who should get 403. The
 * resource checks ownership first, then validates the username itself.</p>
 */
public record MemberCommand(String username) {
}
EOF

# =============================================================================
step "Backend - security/BoardAccess.java"
cat > "$B/security/BoardAccess.java" <<'EOF'
package com.odelia.kanban.security;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.entity.BoardList;
import com.odelia.kanban.entity.Card;
import com.odelia.kanban.repository.BoardListRepository;
import com.odelia.kanban.repository.BoardMemberRepository;
import com.odelia.kanban.repository.BoardRepository;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.ForbiddenException;

/**
 * Authorization for boards and everything inside them.
 *
 * <p>Two levels, both centralized here:</p>
 * <ul>
 *   <li>{@link #requireBoardAccess} - <em>collaborator</em> actions: the owner,
 *       a member or an admin may read the board and work on its columns and
 *       cards. Columns and cards walk up to their board, so members get exactly
 *       the owner's rights on them.</li>
 *   <li>{@link #requireBoardOwnership} - <em>owner-only</em> actions: renaming or
 *       deleting the board and managing its membership. Members are refused.</li>
 * </ul>
 *
 * <p>Membership is read from the database on every request, so removing a
 * member takes effect on their very next call.</p>
 */
@RequestScoped
public class BoardAccess {

    @Inject
    CurrentUser currentUser;

    @Inject
    BoardRepository boards;

    @Inject
    BoardListRepository lists;

    @Inject
    BoardMemberRepository members;

    /** Collaborator check: 403 unless the caller is the owner, a member, or an admin. */
    public void requireBoardAccess(Board board) {
        if (!isOwnerOrAdmin(board) && !isMember(board)) {
            throw new ForbiddenException("Board " + board.getId() + " is not shared with you");
        }
    }

    /** Owner-only check: 403 unless the caller owns the board or is an admin. */
    public void requireBoardOwnership(Board board) {
        if (!isOwnerOrAdmin(board)) {
            throw new ForbiddenException("Only the owner of board " + board.getId() + " can do this");
        }
    }

    /** Collaborator check, reached through the column's board. */
    public void requireColumnAccess(BoardList column) {
        requireBoardAccess(boardOf(column));
    }

    /** Collaborator check, reached through the card's column and then its board. */
    public void requireCardAccess(Card card) {
        requireColumnAccess(columnOf(card));
    }

    private boolean isOwnerOrAdmin(Board board) {
        return currentUser.isAdmin() || currentUser.name().equals(board.getOwner());
    }

    private boolean isMember(Board board) {
        return board.getId() != null
                && members.existsByBoardIdAndUsername(board.getId(), currentUser.name());
    }

    private Board boardOf(BoardList column) {
        return boards.findById(column.getBoardId())
                     .orElseThrow(() -> orphan("column " + column.getId()));
    }

    private BoardList columnOf(Card card) {
        return lists.findById(card.getListId())
                    .orElseThrow(() -> orphan("card " + card.getId()));
    }

    /** With no board to check against, nobody can be shown to own the row: deny. */
    private ForbiddenException orphan(String what) {
        return new ForbiddenException("Cannot establish who owns " + what);
    }
}
EOF

# =============================================================================
step "Backend - resource/BoardResource.java"
cat > "$B/resource/BoardResource.java" <<'EOF'
package com.odelia.kanban.resource;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.entity.BoardList;
import com.odelia.kanban.entity.BoardMember;
import com.odelia.kanban.repository.BoardListRepository;
import com.odelia.kanban.repository.BoardMemberRepository;
import com.odelia.kanban.repository.BoardRepository;
import com.odelia.kanban.repository.CardRepository;
import com.odelia.kanban.security.BoardAccess;
import com.odelia.kanban.security.CurrentUser;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Context;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * CRUD over boards, the lists (columns) they contain, and their members.
 *
 * <p>Every endpoint needs a valid Keycloak token: {@code @RolesAllowed}
 * turns an anonymous call into a 401 and a token without the {@code user} role
 * into a 403. On top of that, {@link BoardAccess} decides per board:
 * collaborator actions (read, columns) for the owner, members and admins;
 * owner-only actions (rename, delete, membership) for the owner and admins.</p>
 */
@Path("/boards")
@RequestScoped
@RolesAllowed({ CurrentUser.USER, CurrentUser.ADMIN })
@SecurityRequirement(name = "bearerAuth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class BoardResource {

    private static final List<String> DEFAULT_LISTS = List.of("To do", "Doing", "Done");

    @Inject
    CurrentUser currentUser;

    @Inject
    BoardAccess access;

    @Inject
    BoardRepository boards;

    @Inject
    BoardListRepository lists;

    @Inject
    CardRepository cards;

    @Inject
    BoardMemberRepository members;

    @Context
    UriInfo uriInfo;

    /** The caller's own boards plus the boards shared with them - or every board, for an admin. */
    @GET
    @Operation(operationId = "getBoards")
    public List<Board> listBoards() {
        if (currentUser.isAdmin()) {
            return boards.findAllSortedByName();
        }
        Map<Long, Board> visible = new LinkedHashMap<>();
        for (Board owned : boards.findByOwnerOrderByNameAsc(currentUser.name())) {
            visible.put(owned.getId(), owned);
        }
        for (BoardMember membership : members.findByUsername(currentUser.name())) {
            boards.findById(membership.getBoardId()).ifPresent(b -> visible.putIfAbsent(b.getId(), b));
        }
        List<Board> result = new ArrayList<>(visible.values());
        result.sort(Comparator.comparing(Board::getName, String.CASE_INSENSITIVE_ORDER));
        return result;
    }

    @GET
    @Path("/{id}")
    public Board getBoard(@PathParam("id") long id) {
        return accessibleBoard(id);
    }

    /**
     * Creates a board and seeds it with the three usual columns, so a new board
     * is immediately usable from the UI. The owner always comes from the token:
     * an {@code owner} sent by the client is ignored.
     */
    @POST
    @Transactional
    public Response createBoard(@Valid Board board) {
        board.setId(null);
        board.setCreatedAt(LocalDateTime.now());
        board.setOwner(currentUser.name());
        Board created = boards.insert(board);
        for (int i = 0; i < DEFAULT_LISTS.size(); i++) {
            lists.insert(new BoardList(created.getId(), DEFAULT_LISTS.get(i), i));
        }
        return Response.created(uriInfo.getAbsolutePathBuilder().path(String.valueOf(created.getId())).build())
                       .entity(created)
                       .build();
    }

    /** Owner-only: a member gets 403. */
    @PUT
    @Path("/{id}")
    @Transactional
    public Board updateBoard(@PathParam("id") long id, @Valid Board board) {
        Board existing = ownedBoard(id);
        existing.setName(board.getName());
        return boards.save(existing);
    }

    /** Owner-only: deletes the board, its columns, their cards and its memberships. */
    @DELETE
    @Path("/{id}")
    @Transactional
    public Response deleteBoard(@PathParam("id") long id) {
        Board existing = ownedBoard(id);
        for (BoardList column : lists.findByBoardIdOrderByPositionAsc(id)) {
            cards.deleteByListId(column.getId());
        }
        lists.deleteByBoardId(id);
        members.deleteByBoardId(id);
        boards.delete(existing);
        return Response.noContent().build();
    }

    @GET
    @Path("/{id}/lists")
    public List<BoardList> listColumns(@PathParam("id") long id) {
        accessibleBoard(id);
        return lists.findByBoardIdOrderByPositionAsc(id);
    }

    @POST
    @Path("/{id}/lists")
    @Transactional
    public Response addColumn(@PathParam("id") long id, @Valid BoardList column) {
        accessibleBoard(id);
        column.setId(null);
        column.setBoardId(id);
        BoardList created = lists.insert(column);
        return Response.created(uriInfo.getBaseUriBuilder().path("lists").path(String.valueOf(created.getId())).build())
                       .entity(created)
                       .build();
    }

    // ---------------------------------------------------------------- members

    /** R3 - the owner, any member, or an admin may list the members. */
    @GET
    @Path("/{id}/members")
    public List<BoardMember> listMembers(@PathParam("id") long id) {
        accessibleBoard(id);
        return members.findByBoardIdOrderByUsernameAsc(id);
    }

    /** R2/R5/R10 - owner or admin only; duplicates and the owner are a 400. */
    @POST
    @Path("/{id}/members")
    @Transactional
    public Response addMember(@PathParam("id") long id, MemberCommand command) {
        Board board = ownedBoard(id); // authorization first: a member always gets 403 (R8)
        if (command == null || command.username() == null || command.username().isBlank()) {
            throw badRequest("A username is required");
        }
        String username = normalize(command.username());
        if (username.length() > 120) {
            throw badRequest("A username is at most 120 characters");
        }
        if (username.equals(board.getOwner())) {
            throw badRequest(username + " owns this board and cannot be added as a member");
        }
        if (members.existsByBoardIdAndUsername(id, username)) {
            throw badRequest(username + " is already a member of this board");
        }
        BoardMember created = members.insert(new BoardMember(id, username));
        return Response.created(uriInfo.getAbsolutePathBuilder().path(username).build())
                       .entity(created)
                       .build();
    }

    /** R4/R10 - owner or admin only; takes effect on the removed member's next request. */
    @DELETE
    @Path("/{id}/members/{username}")
    @Transactional
    public Response removeMember(@PathParam("id") long id, @PathParam("username") String rawUsername) {
        Board board = ownedBoard(id);
        String username = normalize(rawUsername);
        if (username.equals(board.getOwner())) {
            throw badRequest(username + " owns this board and cannot be removed");
        }
        if (members.deleteByBoardIdAndUsername(id, username) == 0) {
            throw new WebApplicationException(username + " is not a member of board " + id,
                                              Response.Status.NOT_FOUND);
        }
        return Response.noContent().build();
    }

    // ---------------------------------------------------------------- helpers

    /** A board the caller may work on (owner, member, admin): 404 if gone, 403 otherwise. */
    private Board accessibleBoard(long id) {
        Board board = boards.findById(id).orElseThrow(() -> notFound(id));
        access.requireBoardAccess(board);
        return board;
    }

    /** A board the caller owns (or admin): 404 if gone, 403 for members and strangers. */
    private Board ownedBoard(long id) {
        Board board = boards.findById(id).orElseThrow(() -> notFound(id));
        access.requireBoardOwnership(board);
        return board;
    }

    private WebApplicationException notFound(long id) {
        return new WebApplicationException("No board with id " + id, Response.Status.NOT_FOUND);
    }

    /** Keycloak stores usernames in lower case: "Bob" must match the "bob" token. */
    private static String normalize(String username) {
        return username.trim().toLowerCase(Locale.ROOT);
    }

    private WebApplicationException badRequest(String message) {
        return new WebApplicationException(
                Response.status(Response.Status.BAD_REQUEST)
                        .type(MediaType.APPLICATION_JSON)
                        .entity(Map.of("error", message))
                        .build());
    }
}
EOF

# =============================================================================
step "Backend - test BoardAccessTest.java"
cat > "$T/security/BoardAccessTest.java" <<'EOF'
package com.odelia.kanban.security;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.repository.BoardMemberRepository;
import jakarta.ws.rs.ForbiddenException;
import java.lang.reflect.Proxy;
import java.util.Set;
import org.junit.jupiter.api.Test;

/** Owner / member / stranger / admin against collaborator and owner-only checks. */
class BoardAccessTest {

    private static Board aliceBoard() {
        Board board = new Board("Sprint", "alice");
        board.setId(1L);
        return board;
    }

    private static BoardAccess as(String user, boolean admin, Set<String> memberUsernames) {
        BoardAccess access = new BoardAccess();
        access.currentUser = new CurrentUser() {
            @Override
            public String name() {
                return user;
            }

            @Override
            public boolean isAdmin() {
                return admin;
            }
        };
        access.members = (BoardMemberRepository) Proxy.newProxyInstance(
                BoardMemberRepository.class.getClassLoader(),
                new Class<?>[] { BoardMemberRepository.class },
                (proxy, method, args) -> {
                    if (method.getName().equals("existsByBoardIdAndUsername")) {
                        return (Long) args[0] == 1L && memberUsernames.contains((String) args[1]);
                    }
                    throw new UnsupportedOperationException(method.getName());
                });
        return access;
    }

    @Test
    void ownerCanCollaborateAndManage() {
        BoardAccess access = as("alice", false, Set.of("bob"));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
        assertDoesNotThrow(() -> access.requireBoardOwnership(aliceBoard()));
    }

    @Test
    void memberCanCollaborateButNotManage() {
        BoardAccess access = as("bob", false, Set.of("bob"));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
        assertThrows(ForbiddenException.class, () -> access.requireBoardOwnership(aliceBoard()));
    }

    @Test
    void strangerIsDeniedEverywhere() {
        BoardAccess access = as("dave", false, Set.of("bob"));
        assertThrows(ForbiddenException.class, () -> access.requireBoardAccess(aliceBoard()));
        assertThrows(ForbiddenException.class, () -> access.requireBoardOwnership(aliceBoard()));
    }

    @Test
    void removedMemberIsDenied() {
        BoardAccess access = as("bob", false, Set.of());
        assertThrows(ForbiddenException.class, () -> access.requireBoardAccess(aliceBoard()));
    }

    @Test
    void adminBypassesEverything() {
        BoardAccess access = as("carol", true, Set.of());
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
        assertDoesNotThrow(() -> access.requireBoardOwnership(aliceBoard()));
    }
}
EOF

# =============================================================================
step "Frontend - models/board.ts"
cat > "$F/models/board.ts" <<'EOF'
/** Mirrors com.odelia.kanban.entity.Board on the backend. */
export interface Board {
  id?: number;
  name: string;
  owner?: string;
  createdAt?: string;
}

/** Mirrors com.odelia.kanban.entity.BoardList: a column of a board. */
export interface BoardList {
  id?: number;
  boardId: number;
  name: string;
  position: number;
}

/** Mirrors com.odelia.kanban.entity.Card: a card in a column. */
export interface Card {
  id?: number;
  listId: number;
  title: string;
  description?: string;
  position: number;
  createdAt?: string;
}

/** Mirrors com.odelia.kanban.entity.BoardMember: a user a board is shared with (never its owner). */
export interface BoardMember {
  id?: number;
  boardId: number;
  username: string;
  createdAt?: string;
}
EOF

# =============================================================================
step "Frontend - services/board.service.ts"
cat > "$F/services/board.service.ts" <<'EOF'
import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';

import { environment } from '../../environments/environment';
import { Board, BoardList, BoardMember, Card } from '../models/board';

/**
 * Single entry point to the Kanban REST API.
 *
 * During development `environment.apiUrl` is `/api` and requests are forwarded
 * to OpenLiberty on port 9080 by proxy.conf.json, so the browser sees a single
 * origin and no CORS pre-flight.
 */
@Injectable({ providedIn: 'root' })
export class BoardService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = `${environment.apiUrl}/boards`;
  private readonly listsUrl = `${environment.apiUrl}/lists`;
  private readonly cardsUrl = `${environment.apiUrl}/cards`;

  getBoards(): Observable<Board[]> {
    return this.http.get<Board[]>(this.baseUrl);
  }

  getBoard(id: number): Observable<Board> {
    return this.http.get<Board>(`${this.baseUrl}/${id}`);
  }

  createBoard(name: string): Observable<Board> {
    return this.http.post<Board>(this.baseUrl, { name });
  }

  renameBoard(id: number, name: string): Observable<Board> {
    return this.http.put<Board>(`${this.baseUrl}/${id}`, { name });
  }

  deleteBoard(id: number): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${id}`);
  }

  getLists(boardId: number): Observable<BoardList[]> {
    return this.http.get<BoardList[]>(`${this.baseUrl}/${boardId}/lists`);
  }

  getCards(listId: number): Observable<Card[]> {
    return this.http.get<Card[]>(`${this.listsUrl}/${listId}/cards`);
  }

  createCard(listId: number, title: string, description?: string): Observable<Card> {
    return this.http.post<Card>(`${this.listsUrl}/${listId}/cards`, { title, description });
  }

  updateCard(id: number, patch: { title: string; description?: string }): Observable<Card> {
    return this.http.put<Card>(`${this.cardsUrl}/${id}`, patch);
  }

  deleteCard(id: number): Observable<void> {
    return this.http.delete<void>(`${this.cardsUrl}/${id}`);
  }

  /** Reorder within a column or move to another one; position is the 0-based target index. */
  moveCard(id: number, targetListId: number, position: number): Observable<Card> {
    return this.http.patch<Card>(`${this.cardsUrl}/${id}/move`, { targetListId, position });
  }

  getMembers(boardId: number): Observable<BoardMember[]> {
    return this.http.get<BoardMember[]>(`${this.baseUrl}/${boardId}/members`);
  }

  addMember(boardId: number, username: string): Observable<BoardMember> {
    return this.http.post<BoardMember>(`${this.baseUrl}/${boardId}/members`, { username });
  }

  removeMember(boardId: number, username: string): Observable<void> {
    return this.http.delete<void>(`${this.baseUrl}/${boardId}/members/${encodeURIComponent(username)}`);
  }
}
EOF

# =============================================================================
step "Frontend - boards/board-members.component.*"
cat > "$F/boards/board-members.component.ts" <<'EOF'
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../auth/auth.service';
import { Board, BoardMember } from '../models/board';
import { BoardService } from '../services/board.service';

/**
 * Members panel of a board (F2-F4): everyone who can open the board sees the
 * members; only the owner (or an admin) gets the add / remove controls. The
 * backend enforces the same rule - hiding the controls is only a convenience.
 */
@Component({
  selector: 'app-board-members',
  imports: [FormsModule],
  templateUrl: './board-members.component.html',
  styleUrl: './board-members.component.css'
})
export class BoardMembersComponent implements OnInit {
  private readonly boardService = inject(BoardService);
  private readonly auth = inject(AuthService);

  readonly board = input.required<Board>();

  readonly members = signal<BoardMember[]>([]);
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  /** Owner or admin: may manage the membership. */
  readonly canManage = computed(
    () => this.auth.isAdmin() || this.board().owner === this.auth.username()
  );

  newUsername = '';

  ngOnInit(): void {
    this.reload();
  }

  reload(): void {
    const boardId = this.board().id;
    if (boardId === undefined) {
      return;
    }
    this.loading.set(true);
    this.error.set(null);
    this.boardService.getMembers(boardId).subscribe({
      next: members => {
        this.members.set(members);
        this.loading.set(false);
      },
      error: err => this.fail('Could not load the members', err)
    });
  }

  addMember(): void {
    const boardId = this.board().id;
    const username = this.newUsername.trim();
    if (boardId === undefined || !username) {
      return;
    }
    this.error.set(null);
    this.boardService.addMember(boardId, username).subscribe({
      next: member => {
        this.members.update(members =>
          [...members, member].sort((a, b) => a.username.localeCompare(b.username))
        );
        this.newUsername = '';
      },
      error: err => this.fail(`Could not add "${username}"`, err)
    });
  }

  removeMember(member: BoardMember): void {
    const boardId = this.board().id;
    if (boardId === undefined) {
      return;
    }
    if (!confirm(`Remove "${member.username}" from this board?`)) {
      return;
    }
    this.error.set(null);
    this.boardService.removeMember(boardId, member.username).subscribe({
      next: () => this.members.update(members => members.filter(m => m.username !== member.username)),
      error: err => this.fail(`Could not remove "${member.username}"`, err)
    });
  }

  private fail(message: string, err: unknown): void {
    console.error(message, err);
    const reason = this.reason(err);
    this.error.set(reason ? `${message}: ${reason}` : message);
    this.loading.set(false);
  }

  /** A readable explanation of the status codes the membership endpoints return. */
  private reason(err: unknown): string | null {
    if (!(err instanceof HttpErrorResponse)) {
      return null;
    }
    const serverMessage = typeof err.error?.error === 'string' ? err.error.error : null;
    switch (err.status) {
      case 400:
        return serverMessage ?? 'already a member, or the owner of the board';
      case 403:
        return 'only the board owner can manage its members';
      case 404:
        return serverMessage ?? 'not found';
      default:
        return null;
    }
  }
}
EOF

cat > "$F/boards/board-members.component.html" <<'EOF'
<section class="members">
  <h3>Members</h3>

  @if (error()) {
    <p class="error">{{ error() }}</p>
  }

  <p class="muted">Owner: <strong>{{ board().owner }}</strong></p>

  @if (loading()) {
    <p class="muted">Loading members…</p>
  } @else if (members().length === 0) {
    <p class="muted">This board is not shared with anyone.</p>
  } @else {
    <ul class="member-list">
      @for (member of members(); track member.username) {
        <li class="member">
          <span>{{ member.username }}</span>
          @if (canManage()) {
            <button class="danger" type="button" (click)="removeMember(member)">Remove</button>
          }
        </li>
      }
    </ul>
  }

  @if (canManage()) {
    <form class="add-member" (ngSubmit)="addMember()">
      <input
        name="newUsername"
        [(ngModel)]="newUsername"
        placeholder="Username to add"
        autocomplete="off"
        maxlength="120" />
      <button type="submit" [disabled]="!newUsername.trim()">Add member</button>
    </form>
  }
</section>
EOF

cat > "$F/boards/board-members.component.css" <<'EOF'
.members {
  margin-top: 1.5rem;
  padding: 1rem;
  border: 1px solid #ddd;
  border-radius: 6px;
  max-width: 28rem;
}

.members h3 {
  margin: 0 0 0.5rem;
}

.member-list {
  list-style: none;
  padding: 0;
  margin: 0 0 0.75rem;
}

.member {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.25rem 0;
}

.add-member {
  display: flex;
  gap: 0.5rem;
}
EOF

# =============================================================================
step "Frontend - boards/board-list.component.ts + .html"
cat > "$F/boards/board-list.component.ts" <<'EOF'
import { Component, OnInit, inject, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { AuthService } from '../auth/auth.service';
import { Board } from '../models/board';
import { BoardService } from '../services/board.service';

/**
 * Lists the boards the user owns or is a member of, creates one, deletes one.
 * Each board name links to the drag-and-drop board detail view ({@code /boards/:id}).
 */
@Component({
  selector: 'app-board-list',
  imports: [FormsModule, DatePipe, RouterLink],
  templateUrl: './board-list.component.html',
  styleUrl: './board-list.component.css'
})
export class BoardListComponent implements OnInit {
  private readonly boardService = inject(BoardService);
  private readonly auth = inject(AuthService);

  readonly boards = signal<Board[]>([]);
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  newBoardName = '';

  ngOnInit(): void {
    this.reload();
  }

  /** True when the signed-in user created the board. */
  isOwner(board: Board): boolean {
    return board.owner === this.auth.username();
  }

  /** F5 - only the owner (or an admin) sees the Delete button. */
  canDelete(board: Board): boolean {
    return this.auth.isAdmin() || this.isOwner(board);
  }

  reload(): void {
    this.loading.set(true);
    this.error.set(null);
    this.boardService.getBoards().subscribe({
      next: boards => {
        this.boards.set(boards);
        this.loading.set(false);
      },
      error: err => this.fail('Could not load the boards', err)
    });
  }

  createBoard(): void {
    const name = this.newBoardName.trim();
    if (!name) {
      return;
    }
    this.error.set(null);
    this.boardService.createBoard(name).subscribe({
      next: board => {
        this.boards.update(boards => [...boards, board].sort((a, b) => a.name.localeCompare(b.name)));
        this.newBoardName = '';
      },
      error: err => this.fail(`Could not create the board "${name}"`, err)
    });
  }

  deleteBoard(board: Board): void {
    if (board.id === undefined) {
      return;
    }
    if (!confirm(`Delete board "${board.name}"? This cannot be undone.`)) {
      return;
    }
    this.error.set(null);
    this.boardService.deleteBoard(board.id).subscribe({
      next: () => this.boards.update(boards => boards.filter(b => b.id !== board.id)),
      error: err => this.fail(`Could not delete the board "${board.name}"`, err)
    });
  }

  private fail(message: string, err: unknown): void {
    console.error(message, err);
    this.error.set(message);
    this.loading.set(false);
  }
}
EOF

cat > "$F/boards/board-list.component.html" <<'EOF'
<section class="boards">
  <form class="new-board" (ngSubmit)="createBoard()">
    <input
      name="newBoardName"
      [(ngModel)]="newBoardName"
      placeholder="New board name"
      autocomplete="off"
      maxlength="120" />
    <button type="submit" [disabled]="!newBoardName.trim()">Create board</button>
    <button type="button" class="ghost" (click)="reload()">Refresh</button>
  </form>

  @if (error()) {
    <p class="error">{{ error() }}</p>
  }

  @if (loading()) {
    <p class="muted">Loading boards…</p>
  } @else if (boards().length === 0) {
    <p class="muted">No board yet. Create the first one above.</p>
  } @else {
    <ul class="board-list">
      @for (board of boards(); track board.id) {
        <li class="board">
          <div class="board-row">
            <a class="board-name" [routerLink]="['/boards', board.id]">
              {{ board.name }}
            </a>
            @if (!isOwner(board)) {
              <span class="badge-shared">shared with you</span>
            }
            <span class="meta">
              {{ board.owner }}
              @if (board.createdAt) {
                · {{ board.createdAt | date: 'short' }}
              }
            </span>
            @if (canDelete(board)) {
              <button class="danger" type="button" (click)="deleteBoard(board)">Delete</button>
            }
          </div>
        </li>
      }
    </ul>
  }
</section>
EOF

if ! grep -q 'badge-shared' "$F/boards/board-list.component.css" 2>/dev/null; then
  cat >> "$F/boards/board-list.component.css" <<'EOF'

.badge-shared {
  font-size: 0.75rem;
  padding: 0.1rem 0.4rem;
  border-radius: 999px;
  background: #e8f0fe;
  color: #1a56db;
}
EOF
fi

# =============================================================================
step "Frontend - patch board-detail.component (.ts + .html)"
node - "$F/boards/board-detail.component.ts" "$F/boards/board-detail.component.html" <<'EOF'
const fs = require('fs');
const [tsPath, htmlPath] = process.argv.slice(2);

let ts = fs.readFileSync(tsPath, 'utf8');
if (!ts.includes('BoardMembersComponent')) {
  const importAnchor = "import { BoardService } from '../services/board.service';";
  const importsRe = /imports:\s*\[([^\]]*)\]/;
  if (!ts.includes(importAnchor) || !importsRe.test(ts)) {
    console.error('ERROR: board-detail.component.ts does not match the expected layout; add BoardMembersComponent manually.');
    process.exit(1);
  }
  ts = ts.replace(importAnchor, `${importAnchor}\nimport { BoardMembersComponent } from './board-members.component';`);
  ts = ts.replace(importsRe, (_, list) => `imports: [${list.trim()}, BoardMembersComponent]`);
  fs.writeFileSync(tsPath, ts);
  console.log('patched', tsPath);
} else {
  console.log('already patched', tsPath);
}

let html = fs.readFileSync(htmlPath, 'utf8');
if (!html.includes('app-board-members')) {
  html = html.replace(/\s*$/, '\n') +
    '\n<!-- Exercise 17: members panel (F2/F3/F4) -->\n' +
    '@if (board(); as b) {\n  <app-board-members [board]="b" />\n}\n';
  fs.writeFileSync(htmlPath, html);
  console.log('patched', htmlPath);
} else {
  console.log('already patched', htmlPath);
}
EOF

# =============================================================================
step "scripts/test-sharing.sh (API checks R2-R10)"
cat > scripts/test-sharing.sh <<'EOF'
#!/usr/bin/env bash
# End-to-end checks for exercise 17. Requires curl + jq and a running stack.
# Run from the HOST (tokens must be minted at localhost:8081, see README).
# Overridable: KC_URL, API_URL, ALICE_PASSWORD, BOB_PASSWORD, CAROL_PASSWORD
set -uo pipefail

KC_URL=${KC_URL:-http://localhost:8081}
API_URL=${API_URL:-http://localhost:9080/api}
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT
FAILS=0

token() {
  curl -s "$KC_URL/realms/kanban/protocol/openid-connect/token" \
    -d grant_type=password -d client_id=kanban-app \
    -d "username=$1" -d "password=$2" | jq -r .access_token
}

# req TOKEN METHOD PATH [JSON] -> prints the HTTP status, body in $BODY
req() {
  local args=(-s -o "$BODY" -w '%{http_code}' -X "$2" -H "Authorization: Bearer $1")
  if [[ $# -ge 4 ]]; then
    args+=(-H 'Content-Type: application/json' -d "$4")
  fi
  curl "${args[@]}" "$API_URL$3"
}

check() { # LABEL EXPECTED ACTUAL
  if [[ "$2" == "$3" ]]; then
    printf '  \033[32mOK\033[0m  %-58s %s\n' "$1" "$3"
  else
    printf '  \033[31mKO\033[0m  %-58s got %s, expected %s\n' "$1" "$3" "$2"
    FAILS=$((FAILS + 1))
  fi
}

ALICE=$(token alice "${ALICE_PASSWORD:-alice}")
BOB=$(token bob "${BOB_PASSWORD:-bob}")
CAROL=$(token carol "${CAROL_PASSWORD:-carol}")
for t in "$ALICE" "$BOB" "$CAROL"; do
  [[ -n "$t" && "$t" != null ]] || { echo "Could not get a token - check Keycloak and passwords."; exit 2; }
done

echo "Setup"
check "alice creates a board" 201 "$(req "$ALICE" POST /boards '{"name":"ex17-test"}')"
BID=$(jq -r .id "$BODY")

echo "R9 - before sharing"
check "bob (stranger) GET board -> 403" 403 "$(req "$BOB" GET "/boards/$BID")"

echo "R2 / R5 / R10 - adding"
check "alice adds bob -> 201" 201 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"bob"}')"
check "alice adds bob again -> 400" 400 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"bob"}')"
check "alice adds herself (owner) -> 400" 400 "$(req "$ALICE" POST "/boards/$BID/members" '{"username":"alice"}')"

echo "R6 - listing"
req "$BOB" GET /boards >/dev/null
if jq -e "map(.id) | index($BID)" "$BODY" >/dev/null; then check "bob's GET /boards includes the shared board" yes yes
else check "bob's GET /boards includes the shared board" yes no; fi

echo "R3 / R7 - member rights"
check "bob GET members -> 200" 200 "$(req "$BOB" GET "/boards/$BID/members")"
check "bob GET board -> 200" 200 "$(req "$BOB" GET "/boards/$BID")"
check "bob GET columns -> 200" 200 "$(req "$BOB" GET "/boards/$BID/lists")"
L1=$(jq -r '.[0].id' "$BODY"); L2=$(jq -r '.[1].id' "$BODY")
check "bob adds a card -> 201" 201 "$(req "$BOB" POST "/lists/$L1/cards" '{"title":"bob card"}')"
CID=$(jq -r .id "$BODY")
check "bob edits the card -> 200" 200 "$(req "$BOB" PUT "/cards/$CID" '{"title":"bob card v2"}')"
check "bob moves the card -> 200" 200 "$(req "$BOB" PATCH "/cards/$CID/move" "{\"targetListId\":$L2,\"position\":0}")"
check "bob adds a column -> 201" 201 "$(req "$BOB" POST "/boards/$BID/lists" '{"name":"Bob column","position":3}')"
COL=$(jq -r .id "$BODY")
check "bob renames the column -> 200" 200 "$(req "$BOB" PUT "/lists/$COL" '{"name":"Bob col 2","position":3}')"
check "bob deletes the card -> 204" 204 "$(req "$BOB" DELETE "/cards/$CID")"
check "bob deletes the column -> 204" 204 "$(req "$BOB" DELETE "/lists/$COL")"

echo "R8 - owner-only actions refused to a member"
check "bob renames the board -> 403" 403 "$(req "$BOB" PUT "/boards/$BID" '{"name":"hacked"}')"
check "bob deletes the board -> 403" 403 "$(req "$BOB" DELETE "/boards/$BID")"
check "bob adds carol -> 403" 403 "$(req "$BOB" POST "/boards/$BID/members" '{"username":"carol"}')"
check "bob removes himself -> 403" 403 "$(req "$BOB" DELETE "/boards/$BID/members/bob")"

echo "Admin"
check "carol (admin) renames the board -> 200" 200 "$(req "$CAROL" PUT "/boards/$BID" '{"name":"ex17-renamed"}')"
check "carol (admin) GET members -> 200" 200 "$(req "$CAROL" GET "/boards/$BID/members")"

echo "R10 / R4 - removing"
check "alice removes herself (owner) -> 400" 400 "$(req "$ALICE" DELETE "/boards/$BID/members/alice")"
check "alice removes bob -> 204" 204 "$(req "$ALICE" DELETE "/boards/$BID/members/bob")"
check "bob's next request is denied -> 403" 403 "$(req "$BOB" GET "/boards/$BID")"

echo "Cleanup"
check "alice deletes the board -> 204" 204 "$(req "$ALICE" DELETE "/boards/$BID")"

echo
if [[ $FAILS -eq 0 ]]; then echo "All checks passed."; else echo "$FAILS check(s) failed."; fi
exit "$FAILS"
EOF
chmod +x scripts/test-sharing.sh

# =============================================================================
if $SKIP_BUILD; then
  step "Build skipped (--skip-build)"
else
  step "Backend - compile + unit tests"
  (cd backend && mvn -q -B test)

  step "Frontend - build"
  (cd frontend && { [[ -d node_modules ]] || npm install; } && npx ng build)
fi

step "Done"
cat <<'EOF'
Next steps:
  1. Restart the backend so Liberty creates the BOARD_MEMBER table:
       - Dev Container: stop and rerun  cd backend && mvn liberty:dev
       - Docker:        docker compose up -d --build backend
  2. From the HOST (curl + jq):  bash scripts/test-sharing.sh
  3. In the browser: alice shares a board with bob, then sign in as bob.
EOF
