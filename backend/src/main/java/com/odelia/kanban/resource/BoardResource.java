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
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Valid;
import jakarta.validation.Validator;
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
import java.util.Set;

/**
 * CRUD over boards, the lists (columns) they contain, and their members.
 *
 * <p>Every endpoint needs a valid Keycloak token: {@code @RolesAllowed}
 * turns an anonymous call into a 401 and a token without the {@code user} role
 * into a 403. On top of that, {@link BoardAccess} decides per board:
 * collaborator actions (read, columns, listing members) for the owner, members
 * and admins; owner-only actions (rename, delete, managing members) for the
 * owner and admins.</p>
 *
 * <p>Owner-only endpoints authorize <em>before</em> they validate their input,
 * so a member always gets 403 and never learns anything from a 400. That is
 * why {@link #updateBoard} and {@link #addMember} validate by hand instead of
 * relying on {@code @Valid}, which would run before the method body.</p>
 */
@Path("/boards")
@RequestScoped
@RolesAllowed({ CurrentUser.USER, CurrentUser.ADMIN })
@SecurityRequirement(name = "bearerAuth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class BoardResource {

    private static final List<String> DEFAULT_LISTS = List.of("To do", "Doing", "Done");

    /** Same bound as {@code BoardMember.username} ({@code @Size(max = 120)}). */
    private static final int MAX_USERNAME = 120;

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

    @Inject
    Validator validator;

    @Context
    UriInfo uriInfo;

    /**
     * R6 - the caller's own boards plus the boards shared with them, each once,
     * sorted by name; every board, for an admin.
     */
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
            if (!visible.containsKey(membership.getBoardId())) {
                boards.findById(membership.getBoardId()).ifPresent(b -> visible.put(b.getId(), b));
            }
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

    /** R8 - owner-only rename: a member gets 403, even with an invalid name. */
    @PUT
    @Path("/{id}")
    @Transactional
    public Board updateBoard(@PathParam("id") long id, Board board) {
        Board existing = ownedBoard(id); // authorization first
        if (board == null) {
            throw badRequest("A board with a name is required");
        }
        existing.setName(board.getName());
        // Same constraints as @Valid would check (@NotBlank, @Size on Board.name),
        // only after authorization. A violation rolls the transaction back.
        Set<ConstraintViolation<Board>> violations = validator.validate(existing);
        if (!violations.isEmpty()) {
            ConstraintViolation<Board> first = violations.iterator().next();
            throw badRequest(first.getPropertyPath() + " " + first.getMessage());
        }
        return boards.save(existing);
    }

    /** R8 - owner-only: deletes the board, its columns, their cards and its memberships. */
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

    /** R7 - a member may add columns, like the owner. */
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

    /** R3 - the owner, any member, or an admin may list the members (never includes the owner). */
    @GET
    @Path("/{id}/members")
    public List<BoardMember> listMembers(@PathParam("id") long id) {
        accessibleBoard(id);
        return members.findByBoardIdOrderByUsernameAsc(id);
    }

    /** R2/R5/R10 - owner or admin only; a duplicate or the owner is a 400. */
    @POST
    @Path("/{id}/members")
    @Transactional
    public Response addMember(@PathParam("id") long id, MemberCommand command) {
        Board board = ownedBoard(id); // authorization first: a member always gets 403 (R8)
        if (command == null || command.username() == null || command.username().isBlank()) {
            throw badRequest("A username is required");
        }
        String username = normalize(command.username());
        if (username.length() > MAX_USERNAME) {
            throw badRequest("A username is at most " + MAX_USERNAME + " characters");
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

    /**
     * R4/R10 - owner or admin only. Removal takes effect on the removed member's
     * next request, since {@link BoardAccess} reads membership every time. A
     * member cannot remove anyone - not even themselves (R8).
     */
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
