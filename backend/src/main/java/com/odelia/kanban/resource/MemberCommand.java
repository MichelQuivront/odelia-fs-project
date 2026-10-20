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
