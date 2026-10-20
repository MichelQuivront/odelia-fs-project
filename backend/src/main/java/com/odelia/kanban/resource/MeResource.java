package com.odelia.kanban.resource;

import com.odelia.kanban.security.CurrentUser;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;

/**
 * {@code GET /api/me}: who the backend thinks the caller is.
 *
 * <p>Everything comes from {@link CurrentUser}, so the username, the roles and
 * the admin flag are interpreted exactly as they are for board ownership - the
 * claims are never parsed a second time here, and the bearer string is never
 * touched. A missing or invalid token is a 401 (MP-JWT), a token without the
 * {@code user} role a 403 ({@code @RolesAllowed}).</p>
 */
@Path("/me")
@RequestScoped
@RolesAllowed(CurrentUser.USER)
@SecurityRequirement(name = "bearerAuth")
@Produces(MediaType.APPLICATION_JSON)
public class MeResource {

    @Inject
    CurrentUser currentUser;

    @GET
    @Operation(operationId = "getCurrentUser", summary = "The signed-in caller, as read from the validated token")
    public CurrentUserView me() {
        return new CurrentUserView(currentUser.name(), currentUser.roles(), currentUser.isAdmin());
    }
}
