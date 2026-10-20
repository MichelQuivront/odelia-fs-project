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
