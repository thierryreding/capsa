from __future__ import annotations

from conftest import PASSWORD

from capsa.sessions import DAY_MS, RENEW_AFTER_MS

LOGIN = "/api/v1/auth/login"


def test_login_sets_strict_httponly_cookie(api):
    api.add_user("lena")
    r = api.client().post(LOGIN, json={"username": "Lena", "password": PASSWORD})
    assert r.status_code == 200
    assert r.json()["username"] == "lena"
    cookie = r.headers["set-cookie"]
    for part in ("capsa_session=", "HttpOnly", "Secure", "SameSite=strict", "Path=/api",
                 f"Max-Age={90 * 24 * 3600}"):  # fmt: skip
        assert part.lower() in cookie.lower(), part


def test_me_requires_session(api):
    assert api.client().get("/api/v1/me").status_code == 401
    api.add_user("lena")
    me = api.login("lena").get("/api/v1/me").json()
    assert (me["username"], me["role"]) == ("lena", "learner")


def test_wrong_password_and_unknown_user_look_the_same(api):
    api.add_user("lena")
    c = api.client()
    a = c.post(LOGIN, json={"username": "lena", "password": "falsch123"})
    b = c.post(LOGIN, json={"username": "nobody", "password": "falsch123"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


def test_logout_revokes_session(api):
    api.add_user("lena")
    c = api.login("lena")
    cookie = c.cookies.get("capsa_session")
    assert c.post("/api/v1/auth/logout").status_code == 204
    other = api.client()
    other.cookies.set("capsa_session", cookie, domain="capsa.test", path="/api")
    assert other.get("/api/v1/me").status_code == 401


def test_session_slides_and_expires(api):
    api.add_user("lena")
    c = api.login("lena")
    api.clock.advance(RENEW_AFTER_MS - 1)
    r = c.get("/api/v1/me")
    assert r.status_code == 200 and "set-cookie" not in r.headers  # no renewal yet
    api.clock.advance(1)
    r = c.get("/api/v1/me")
    assert "capsa_session=" in r.headers["set-cookie"]  # renewed
    api.clock.advance(89 * DAY_MS)
    assert c.get("/api/v1/me").status_code == 200  # still valid: expiry slid forward
    api.clock.advance(91 * DAY_MS)
    assert c.get("/api/v1/me").status_code == 401


def test_disabled_user_loses_access(api):
    from capsa import accounts

    user = api.add_user("lena")
    c = api.login("lena")
    with api.engine.begin() as conn:
        accounts.set_disabled(conn, user.id, True, api.clock())
    assert c.get("/api/v1/me").status_code == 401
    r = api.client().post(LOGIN, json={"username": "lena", "password": PASSWORD})
    assert r.status_code == 401


def test_login_rate_limit(api):
    api.add_user("lena")
    c = api.client()
    for _ in range(5):
        assert c.post(LOGIN, json={"username": "lena", "password": "falsch123"}).status_code == 401
    r = c.post(LOGIN, json={"username": "lena", "password": PASSWORD})
    assert r.status_code == 429
    assert int(r.headers["retry-after"]) == 15 * 60
    api.clock.advance(15 * 60 * 1000)
    assert c.post(LOGIN, json={"username": "lena", "password": PASSWORD}).status_code == 200


def test_rate_limit_per_client_across_usernames(api):
    c = api.client()
    for i in range(20):
        c.post(LOGIN, json={"username": f"user{i}", "password": "falsch123"})
    api.add_user("lena")
    assert c.post(LOGIN, json={"username": "lena", "password": PASSWORD}).status_code == 429


def test_change_password(api):
    api.add_user("lena")
    c = api.login("lena")
    other_device = api.login("lena")
    url = "/api/v1/me/password"
    bad = c.put(url, json={"current_password": "falsch123", "new_password": "neues-passwort"})
    assert bad.status_code == 403
    short = c.put(url, json={"current_password": PASSWORD, "new_password": "kurz"})
    assert short.status_code == 400 and "at least 8" in short.json()["detail"]
    ok = c.put(url, json={"current_password": PASSWORD, "new_password": "neues-passwort"})
    assert ok.status_code == 204
    assert c.get("/api/v1/me").status_code == 200  # this session stays
    assert other_device.get("/api/v1/me").status_code == 401  # others are signed out
    api.login("lena", "neues-passwort")
