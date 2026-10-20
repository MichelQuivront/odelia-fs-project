package com.odelia.kanban.security;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.entity.BoardList;
import com.odelia.kanban.repository.BoardListRepository;
import com.odelia.kanban.repository.BoardMemberRepository;
import com.odelia.kanban.repository.BoardRepository;
import jakarta.ws.rs.ForbiddenException;
import java.lang.reflect.Proxy;
import java.util.HashSet;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.Test;

/**
 * The board authorization rules as executable tests against {@link BoardAccess} -
 * no CDI container, no database.
 *
 * <p>Exercise 15: owner / other user / admin against {@code requireBoardAccess}.
 * Exercise 17: members get the collaborator level but not the owner-only one.</p>
 */
class BoardAccessTest {

    /** Usernames that are members of board 1, read live by the fake repository. */
    private final Set<String> membersOfBoard1 = new HashSet<>();

    private static Board aliceBoard() {
        Board board = new Board("Sprint", "alice");
        board.setId(1L);
        return board;
    }

    /** A BoardAccess wired by hand, as CDI would, for the given caller. */
    private BoardAccess accessFor(CurrentUser caller) {
        BoardAccess access = new BoardAccess();
        access.currentUser = caller;
        access.members = (BoardMemberRepository) Proxy.newProxyInstance(
                BoardMemberRepository.class.getClassLoader(),
                new Class<?>[] { BoardMemberRepository.class },
                (proxy, method, args) -> {
                    if (method.getName().equals("existsByBoardIdAndUsername")) {
                        return (Long) args[0] == 1L && membersOfBoard1.contains((String) args[1]);
                    }
                    throw new UnsupportedOperationException(method.getName());
                });
        return access;
    }

    // ----------------------------------------------- exercise 15: three rules

    @Test
    void ownerIsAllowed() {
        BoardAccess access = accessFor(new StubCurrentUser("alice", false));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
    }

    @Test
    void otherNonAdminUserIsForbidden() {
        BoardAccess access = accessFor(new StubCurrentUser("bob", false));
        assertThrows(ForbiddenException.class, () -> access.requireBoardAccess(aliceBoard()));
    }

    @Test
    void adminIsAlwaysAllowed() {
        BoardAccess access = accessFor(new StubCurrentUser("carol", true));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
    }

    // ----------------------------------------------- exercise 15: stretch

    @SuppressWarnings("unchecked")
    private static <R> R findByIdOnly(Class<R> type, Map<Long, ?> rows) {
        return (R) Proxy.newProxyInstance(type.getClassLoader(), new Class<?>[] { type },
                (proxy, method, args) -> {
                    if (method.getName().equals("findById")) {
                        return Optional.ofNullable(rows.get((Long) args[0]));
                    }
                    throw new UnsupportedOperationException(method.getName());
                });
    }

    private static BoardList column(long id, long boardId) {
        BoardList column = new BoardList(boardId, "To do", 0);
        column.setId(id);
        return column;
    }

    @Test
    void columnAccessWalksUpToTheBoardOwner() {
        BoardAccess asAlice = accessFor(new StubCurrentUser("alice", false));
        asAlice.boards = findByIdOnly(BoardRepository.class, Map.of(1L, aliceBoard()));
        BoardAccess asBob = accessFor(new StubCurrentUser("bob", false));
        asBob.boards = asAlice.boards;

        assertDoesNotThrow(() -> asAlice.requireColumnAccess(column(10L, 1L)));
        assertThrows(ForbiddenException.class, () -> asBob.requireColumnAccess(column(10L, 1L)));
    }

    @Test
    void orphanColumnIsDeniedEvenToItsWouldBeOwner() {
        BoardAccess access = accessFor(new StubCurrentUser("alice", false));
        access.boards = findByIdOnly(BoardRepository.class, Map.of()); // board 1 no longer exists
        access.lists = findByIdOnly(BoardListRepository.class, Map.of());

        assertThrows(ForbiddenException.class, () -> access.requireColumnAccess(column(10L, 1L)));
    }

    // ----------------------------------------------- exercise 17: members

    @Test
    void ownerCanCollaborateAndManage() {
        membersOfBoard1.add("bob");
        BoardAccess access = accessFor(new StubCurrentUser("alice", false));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
        assertDoesNotThrow(() -> access.requireBoardOwnership(aliceBoard()));
    }

    @Test
    void memberCanCollaborateButNotManage() {
        membersOfBoard1.add("bob");
        BoardAccess access = accessFor(new StubCurrentUser("bob", false));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));                         // R7
        assertThrows(ForbiddenException.class, () -> access.requireBoardOwnership(aliceBoard()));  // R8
    }

    @Test
    void memberReachesColumnsThroughTheBoard() {
        membersOfBoard1.add("bob");
        BoardAccess access = accessFor(new StubCurrentUser("bob", false));
        access.boards = findByIdOnly(BoardRepository.class, Map.of(1L, aliceBoard()));
        assertDoesNotThrow(() -> access.requireColumnAccess(column(10L, 1L)));                     // R7
    }

    @Test
    void strangerIsDeniedEverywhere() {
        membersOfBoard1.add("bob");
        BoardAccess access = accessFor(new StubCurrentUser("dave", false));
        assertThrows(ForbiddenException.class, () -> access.requireBoardAccess(aliceBoard()));     // R9
        assertThrows(ForbiddenException.class, () -> access.requireBoardOwnership(aliceBoard()));
    }

    @Test
    void removedMemberIsDeniedOnTheNextCheck() {
        membersOfBoard1.add("bob");
        BoardAccess access = accessFor(new StubCurrentUser("bob", false));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));

        membersOfBoard1.remove("bob"); // DELETE /members/bob committed meanwhile

        assertThrows(ForbiddenException.class, () -> access.requireBoardAccess(aliceBoard()));     // R4
    }

    @Test
    void adminBypassesBothLevels() {
        BoardAccess access = accessFor(new StubCurrentUser("carol", true));
        assertDoesNotThrow(() -> access.requireBoardAccess(aliceBoard()));
        assertDoesNotThrow(() -> access.requireBoardOwnership(aliceBoard()));
    }
}
