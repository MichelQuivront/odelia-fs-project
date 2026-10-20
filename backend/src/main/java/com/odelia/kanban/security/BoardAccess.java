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
 * <p>{@code @RolesAllowed} alone only answers "is this a signed-in Kanban
 * user?", which is not enough: every user has the {@code user} role, so without
 * these checks anyone could read someone else's board by guessing its id. The
 * coarse role check and this fine-grained one are complementary.</p>
 *
 * <p>Two levels, both decided here and nowhere else:</p>
 * <ul>
 *   <li>{@link #requireBoardAccess} - <em>collaborator</em> actions: the owner,
 *       a member or an admin may read the board and work on its columns and
 *       cards. Columns and cards store no owner of their own; they walk up to
 *       their board, so a member gets exactly the owner's rights on them.</li>
 *   <li>{@link #requireBoardOwnership} - <em>owner-only</em> actions: renaming or
 *       deleting the board and managing its membership. Members are refused.</li>
 * </ul>
 *
 * <p>The owner is never a {@code BoardMember} row: {@link Board#getOwner()}
 * answers that. Membership is read from the database on every request, so a
 * removed member is refused on their very next call.</p>
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

    /** Only asked when the cheaper owner/admin test failed, so owners never hit the table. */
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
