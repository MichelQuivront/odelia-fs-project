package com.odelia.kanban.resource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.odelia.kanban.security.CurrentUser;
import java.lang.reflect.Proxy;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.eclipse.microprofile.jwt.JsonWebToken;
import org.junit.jupiter.api.Test;

/**
 * {@code GET /api/me} against a real {@link CurrentUser} fed by a fake token,
 * so the test covers the claim interpretation as well as the resource.
 */
class MeResourceTest {

    /** A JsonWebToken answering only getClaim / getGroups, built with a JDK dynamic proxy. */
    private static JsonWebToken token(Map<String, Object> claims) {
        return (JsonWebToken) Proxy.newProxyInstance(
                JsonWebToken.class.getClassLoader(),
                new Class<?>[] { JsonWebToken.class },
                (proxy, method, args) -> switch (method.getName()) {
                    case "getClaim" -> claims.get(String.valueOf(args[0]));
                    case "getGroups" -> claims.get("groups");
                    case "getSubject" -> claims.get("sub");
                    case "claim" -> java.util.Optional.ofNullable(claims.get(String.valueOf(args[0])));
                    default -> {
                        if (method.isDefault()) {
                            yield java.lang.reflect.InvocationHandler.invokeDefault(proxy, method, args);
                        }
                        throw new UnsupportedOperationException(method.getName());
                    }
                });
    }

    private static CurrentUserView meFor(Map<String, Object> claims) throws Exception {
        CurrentUser currentUser = new CurrentUser();
        var jwtField = CurrentUser.class.getDeclaredField("jwt");
        jwtField.setAccessible(true);
        jwtField.set(currentUser, token(claims));
        MeResource resource = new MeResource();
        resource.currentUser = currentUser;
        return resource.me();
    }

    @Test
    void userGetsTheirNameAndRoles() throws Exception {
        CurrentUserView me = meFor(Map.of("preferred_username", "alice", "sub", "uuid-a",
                                          "groups", Set.of("user")));
        assertEquals("alice", me.username());
        assertEquals(List.of("user"), me.roles());
        assertFalse(me.admin());
    }

    @Test
    void adminRolesAreSortedAndFlagged() throws Exception {
        CurrentUserView me = meFor(Map.of("preferred_username", "carol", "sub", "uuid-c",
                                          "groups", Set.of("user", "admin")));
        assertEquals("carol", me.username());
        assertEquals(List.of("admin", "user"), me.roles());
        assertTrue(me.admin());
    }

    @Test
    void missingGroupsClaimMeansNoRolesNotNull() throws Exception {
        CurrentUserView me = meFor(Map.of("preferred_username", "bob", "sub", "uuid-b"));
        assertEquals(List.of(), me.roles());
        assertFalse(me.admin());
    }

    @Test
    void responseNeverCarriesTheRawToken() {
        // The record's components are the whole JSON surface: no token, no subject.
        var names = java.util.Arrays.stream(CurrentUserView.class.getRecordComponents())
                                    .map(java.lang.reflect.RecordComponent::getName).toList();
        assertEquals(List.of("username", "roles", "admin"), names);
    }
}
