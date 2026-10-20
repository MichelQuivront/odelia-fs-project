package com.odelia.kanban.security;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.odelia.kanban.entity.Board;
import com.odelia.kanban.entity.BoardList;
import com.odelia.kanban.repository.BoardListRepository;
import com.odelia.kanban.repository.BoardRepository;
import jakarta.ws.rs.ForbiddenException;
import java.lang.reflect.Proxy;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * The ownership rule "a user can only see/modify their own boards", as
 * executable tests against {@link BoardAccess} - no CDI container, no database.
 */
class BoardAccessTest {

    private static Board aliceBoard() {
        Board board = new Board("Sprint", "alice");
        board.setId(1L);
        return board;
    }

    /** A BoardAccess wired by hand, as CDI would, for the given caller. */
    private static BoardAccess accessFor(CurrentUser caller) {
        BoardAccess access = new BoardAccess();
        access.currentUser = caller;
        return access;
    }

    // ------------------------------------------------------- the three rules

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

    // ------------------------------------------------------- stretch: columns

    /**
     * A read-only, in-memory stand-in for a Jakarta Data repository: only
     * {@code findById} is answered, anything else fails the test loudly.
     */
    @SuppressWarnings("unchecked")
    private static <R> R repository(Class<R> type, Map<Long, ?> rows) {
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
        asAlice.boards = repository(BoardRepository.class, Map.of(1L, aliceBoard()));
        BoardAccess asBob = accessFor(new StubCurrentUser("bob", false));
        asBob.boards = asAlice.boards;

        assertDoesNotThrow(() -> asAlice.requireColumnAccess(column(10L, 1L)));
        assertThrows(ForbiddenException.class, () -> asBob.requireColumnAccess(column(10L, 1L)));
    }

    @Test
    void orphanColumnIsDeniedEvenToItsWouldBeOwner() {
        BoardAccess access = accessFor(new StubCurrentUser("alice", false));
        access.boards = repository(BoardRepository.class, Map.of()); // board 1 no longer exists
        access.lists = repository(BoardListRepository.class, Map.of());

        assertThrows(ForbiddenException.class, () -> access.requireColumnAccess(column(10L, 1L)));
    }
}
