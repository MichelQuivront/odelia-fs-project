package com.odelia.kanban.security;

import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.jwt.Claims;
import org.eclipse.microprofile.jwt.JsonWebToken;

import java.util.List;
import java.util.Set;

/**
 * The caller, as described by the bearer token.
 *
 * <p>By the time a resource method runs, the mpJwt feature has already checked
 * the token's signature (against Keycloak's JWKS), issuer, audience and expiry,
 * and turned its {@code groups} claim into Jakarta EE roles - that is what makes
 * {@code @RolesAllowed} work. Injecting {@link JsonWebToken} is all it takes to
 * read the token itself; this class only adds the two Kanban-specific questions
 * on top of it: "who is this?" and "is this an admin?".</p>
 */
@RequestScoped
public class CurrentUser {

    /** Realm role carried by every signed-in Kanban user. */
    public static final String USER = "user";

    /** Realm role allowed to see and change every board, not only its own. */
    public static final String ADMIN = "admin";

    @Inject
    JsonWebToken jwt;

    /**
     * The name a board is owned by.
     *
     * <p>Read {@code preferred_username} directly rather than
     * {@link JsonWebToken#getName()}: {@code getName()} follows the runtime's
     * {@code userNameAttribute} (here {@code upn}, mapped from the username by
     * the realm), whereas a board owner should always be the human-readable
     * username. The subject (a UUID) stays as a last resort.</p>
     */
    public String name() {
        return jwt.<String>claim(Claims.preferred_username)
                  .filter(name -> !name.isBlank())
                  .orElseGet(jwt::getSubject);
    }

    /**
     * True when the token carries the {@code admin} realm role. The realm maps
     * realm roles into the {@code groups} claim that MicroProfile JWT expects.
     */
    public boolean isAdmin() {
        return jwt.getGroups() != null && jwt.getGroups().contains(ADMIN);
    }

    /**
     * The caller's realm roles, from the same validated {@code groups} claim that
     * {@code @RolesAllowed} and {@link #isAdmin()} read. Sorted, so the JSON is
     * deterministic; empty rather than null when the claim is missing.
     */
    public List<String> roles() {
        Set<String> groups = jwt.getGroups();
        return groups == null ? List.of() : groups.stream().sorted().toList();
    }
}
