package com.odelia.kanban.resource;

import java.util.List;

/**
 * Body of {@code GET /api/me}: a safe, read-only view of the caller.
 *
 * <p>A record rather than an entity: nothing here is persisted, it is derived
 * from the already-validated JWT on every request. It deliberately carries no
 * raw token, no subject UUID and no expiry - only what the UI needs to know who
 * is signed in and what they may do.</p>
 *
 * @param username the same name boards are owned by ({@code preferred_username})
 * @param roles    the caller's realm roles, sorted
 * @param admin    whether the caller bypasses board ownership checks
 */
public record CurrentUserView(String username, List<String> roles, boolean admin) {
}
