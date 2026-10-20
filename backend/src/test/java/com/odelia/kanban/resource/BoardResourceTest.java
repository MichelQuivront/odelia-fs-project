package com.odelia.kanban.resource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.entity.BoardList;
import com.odelia.kanban.entity.BoardMember;
import com.odelia.kanban.repository.BoardListRepository;
import com.odelia.kanban.repository.BoardMemberRepository;
import com.odelia.kanban.repository.BoardRepository;
import com.odelia.kanban.repository.CardRepository;
import com.odelia.kanban.security.BoardAccess;
import com.odelia.kanban.security.CurrentUser;
import jakarta.validation.Validator;
import jakarta.ws.rs.ForbiddenException;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import jakarta.ws.rs.core.UriInfo;
import java.lang.reflect.Field;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Exercise 17 at the resource level: R2-R10 through {@link BoardResource}, with
 * a real {@link BoardAccess} and in-memory fakes of the Jakarta Data
 * repositories (JDK proxies, no mocking library).
 *
 * <p>Board 1 "Sprint" and board 2 "Alpha" belong to alice; board 3 "Bob's" to bob.</p>
 */
class BoardResourceTest {

    private final Map<Long, Board> boardRows = new HashMap<>();
    private final List<BoardMember> memberRows = new ArrayList<>();
    private final List<String> deletedListsOfBoards = new ArrayList<>();

    @BeforeEach
    void seed() {
        board(1L, "Sprint", "alice");
        board(2L, "Alpha", "alice");
        board(3L, "Bob's", "bob");
    }

    private void board(long id, String name, String owner) {
        Board b = new Board(name, owner);
        b.setId(id);
        boardRows.put(id, b);
    }

    private void member(long boardId, String username) {
        memberRows.add(new BoardMember(boardId, username));
    }

    // ------------------------------------------------------------- fixtures

    @SuppressWarnings("unchecked")
    private static <R> R fake(Class<R> type, java.util.function.BiFunction<String, Object[], Object> answer) {
        return (R) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] { type },
                (proxy, method, args) -> answer.apply(method.getName(), args));
    }

    private BoardResource as(String user, boolean admin) throws Exception {
        CurrentUser caller = new CurrentUser() {
            @Override
            public String name() {
                return user;
            }

            @Override
            public boolean isAdmin() {
                return admin;
            }
        };

        BoardRepository boards = fake(BoardRepository.class, (m, a) -> switch (m) {
            case "findById" -> Optional.ofNullable(boardRows.get((Long) a[0]));
            case "findAllSortedByName" -> boardRows.values().stream()
                    .sorted(Comparator.comparing(Board::getName)).toList();
            case "findByOwnerOrderByNameAsc" -> boardRows.values().stream()
                    .filter(b -> b.getOwner().equals(a[0])).sorted(Comparator.comparing(Board::getName)).toList();
            case "save" -> a[0];
            case "delete" -> boardRows.remove(((Board) a[0]).getId());
            default -> throw new UnsupportedOperationException(m);
        });
        BoardMemberRepository members = fake(BoardMemberRepository.class, (m, a) -> switch (m) {
            case "existsByBoardIdAndUsername" -> memberRows.stream()
                    .anyMatch(r -> r.getBoardId() == (Long) a[0] && r.getUsername().equals(a[1]));
            case "findByUsername" -> memberRows.stream().filter(r -> r.getUsername().equals(a[0])).toList();
            case "findByBoardIdOrderByUsernameAsc" -> memberRows.stream()
                    .filter(r -> r.getBoardId() == (Long) a[0])
                    .sorted(Comparator.comparing(BoardMember::getUsername)).toList();
            case "insert" -> {
                memberRows.add((BoardMember) a[0]);
                yield a[0];
            }
            case "deleteByBoardIdAndUsername" -> {
                int before = memberRows.size();
                memberRows.removeIf(r -> r.getBoardId() == (Long) a[0] && r.getUsername().equals(a[1]));
                yield (long) (before - memberRows.size());
            }
            case "deleteByBoardId" -> {
                memberRows.removeIf(r -> r.getBoardId() == (Long) a[0]);
                yield null;
            }
            default -> throw new UnsupportedOperationException(m);
        });
        BoardListRepository lists = fake(BoardListRepository.class, (m, a) -> switch (m) {
            case "findByBoardIdOrderByPositionAsc" -> List.<BoardList>of();
            case "deleteByBoardId" -> {
                deletedListsOfBoards.add(String.valueOf(a[0]));
                yield null;
            }
            default -> throw new UnsupportedOperationException(m);
        });
        CardRepository cards = fake(CardRepository.class, (m, a) -> {
            throw new UnsupportedOperationException(m);
        });
        // Board has @NotBlank/@Size on name; the fake reports a violation-free result
        // for any non-blank name, which is all updateBoard needs from it here.
        Validator validator = fake(Validator.class, (m, a) -> {
            if (m.equals("validate")) {
                String name = ((Board) a[0]).getName();
                if (name == null || name.isBlank()) {
                    throw new AssertionError("blank names are rejected by the real validator; not exercised here");
                }
                return Set.of();
            }
            throw new UnsupportedOperationException(m);
        });

        BoardAccess access = new BoardAccess();
        set(access, "currentUser", caller);
        set(access, "boards", boards);
        set(access, "lists", lists);
        set(access, "members", members);

        BoardResource resource = new BoardResource();
        resource.currentUser = caller;
        resource.access = access;
        resource.boards = boards;
        resource.lists = lists;
        resource.cards = cards;
        resource.members = members;
        resource.validator = validator;
        resource.uriInfo = fake(UriInfo.class, (m, a) -> switch (m) {
            case "getAbsolutePathBuilder", "getBaseUriBuilder" -> UriBuilder.fromUri("http://localhost:9080/api/boards/1/members");
            default -> throw new UnsupportedOperationException(m);
        });
        return resource;
    }

    /** BoardAccess's fields are package-private to its own package; set them reflectively. */
    private static void set(Object target, String field, Object value) throws Exception {
        Field f = target.getClass().getDeclaredField(field);
        f.setAccessible(true);
        f.set(target, value);
    }

    private static int status(WebApplicationException e) {
        return e.getResponse().getStatus();
    }

    private List<String> membersOf(long boardId) {
        return memberRows.stream().filter(r -> r.getBoardId() == boardId).map(BoardMember::getUsername).sorted().toList();
    }

    // ------------------------------------------------------------- R2 / R5 / R10

    @Test
    void ownerAddsAMemberNormalizedToLowerCase() throws Exception {
        Response response = as("alice", false).addMember(1L, new MemberCommand("  Bob "));
        assertEquals(201, response.getStatus());
        assertEquals(List.of("bob"), membersOf(1L));
        assertEquals("bob", ((BoardMember) response.getEntity()).getUsername());
    }

    @Test
    void duplicateMemberIs400AndNotStoredTwice() throws Exception {
        member(1L, "bob");
        WebApplicationException e = assertThrows(WebApplicationException.class,
                () -> as("alice", false).addMember(1L, new MemberCommand("BOB")));
        assertEquals(400, status(e));
        assertEquals(List.of("bob"), membersOf(1L));
    }

    @Test
    void ownerCannotAddOrRemoveThemselves() throws Exception {
        BoardResource alice = as("alice", false);
        assertEquals(400, status(assertThrows(WebApplicationException.class,
                () -> alice.addMember(1L, new MemberCommand("Alice")))));
        assertEquals(400, status(assertThrows(WebApplicationException.class,
                () -> alice.removeMember(1L, "alice"))));
        assertTrue(membersOf(1L).isEmpty());
    }

    @Test
    void blankUsernameIs400ForTheOwner() throws Exception {
        assertEquals(400, status(assertThrows(WebApplicationException.class,
                () -> as("alice", false).addMember(1L, new MemberCommand("  ")))));
    }

    // ------------------------------------------------------------- R8: 403 before 400

    @Test
    void memberGets403NotA400OnEveryOwnerOnlyAction() throws Exception {
        member(1L, "bob");
        BoardResource bob = as("bob", false);
        Board blank = new Board("", null);

        assertThrows(ForbiddenException.class, () -> bob.addMember(1L, new MemberCommand("")));     // invalid body
        assertThrows(ForbiddenException.class, () -> bob.addMember(1L, null));                      // no body
        assertThrows(ForbiddenException.class, () -> bob.addMember(1L, new MemberCommand("alice"))); // owner
        assertThrows(ForbiddenException.class, () -> bob.updateBoard(1L, blank));                   // invalid name
        assertThrows(ForbiddenException.class, () -> bob.updateBoard(1L, new Board("hacked", null)));
        assertThrows(ForbiddenException.class, () -> bob.deleteBoard(1L));
        assertThrows(ForbiddenException.class, () -> bob.removeMember(1L, "bob"));                  // himself
        assertEquals("Sprint", boardRows.get(1L).getName());
        assertEquals(List.of("bob"), membersOf(1L));
    }

    @Test
    void memberCannotRemoveAnotherMember() throws Exception {
        member(1L, "bob");
        member(1L, "dave");
        assertThrows(ForbiddenException.class, () -> as("bob", false).removeMember(1L, "dave"));
        assertEquals(List.of("bob", "dave"), membersOf(1L));
    }

    // ------------------------------------------------------------- R3 / R4 / R9

    @Test
    void memberListsMembersStrangerDoesNot() throws Exception {
        member(1L, "bob");
        assertEquals(List.of("bob"), as("bob", false).listMembers(1L).stream().map(BoardMember::getUsername).toList());
        assertThrows(ForbiddenException.class, () -> as("dave", false).listMembers(1L));
        assertThrows(ForbiddenException.class, () -> as("dave", false).getBoard(1L));
    }

    @Test
    void removalIsImmediateAndUnknownMemberIs404() throws Exception {
        member(1L, "bob");
        assertEquals(204, as("alice", false).removeMember(1L, "BOB").getStatus());
        assertThrows(ForbiddenException.class, () -> as("bob", false).getBoard(1L));
        assertEquals(404, status(assertThrows(WebApplicationException.class,
                () -> as("alice", false).removeMember(1L, "bob"))));
    }

    // ------------------------------------------------------------- R6

    @Test
    void listingMergesOwnedAndSharedBoardsOnceSortedByName() throws Exception {
        member(1L, "bob");
        member(1L, "bob"); // even a duplicated row must not duplicate the board
        member(3L, "bob"); // a stray row on his own board must not duplicate it either
        List<String> names = as("bob", false).listBoards().stream().map(Board::getName).toList();
        assertEquals(List.of("Bob's", "Sprint"), names);
    }

    @Test
    void adminStillSeesEveryBoard() throws Exception {
        assertEquals(3, as("carol", true).listBoards().size());
    }

    // ------------------------------------------------------------- admin / cascade

    @Test
    void adminManagesMembersAndOwnerOnlyActions() throws Exception {
        BoardResource carol = as("carol", true);
        assertEquals(201, carol.addMember(1L, new MemberCommand("bob")).getStatus());
        assertEquals("Renamed", carol.updateBoard(1L, new Board("Renamed", null)).getName());
        assertEquals(204, carol.removeMember(1L, "bob").getStatus());
    }

    @Test
    void deletingABoardDeletesItsMemberships() throws Exception {
        member(1L, "bob");
        member(2L, "bob");
        assertEquals(204, as("alice", false).deleteBoard(1L).getStatus());
        assertFalse(boardRows.containsKey(1L));
        assertTrue(membersOf(1L).isEmpty());
        assertEquals(List.of("bob"), membersOf(2L)); // other boards untouched
        assertEquals(List.of("1"), deletedListsOfBoards);
    }
}
