package com.odelia.kanban.security;

/**
 * A hand-written test double for {@link CurrentUser}: a subclass that returns
 * fixed answers instead of reading a JWT. It is a <em>stub</em>, not a mock -
 * it only supplies canned values and records nothing about how it was called.
 */
class StubCurrentUser extends CurrentUser {

    private final String name;
    private final boolean admin;

    StubCurrentUser(String name, boolean admin) {
        this.name = name;
        this.admin = admin;
    }

    @Override
    public String name() {
        return name;
    }

    @Override
    public boolean isAdmin() {
        return admin;
    }
}
