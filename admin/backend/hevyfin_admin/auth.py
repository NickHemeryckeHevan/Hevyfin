"""Sign in with a Hevyfin (Jellyfin) account; only administrators get in."""
from flask import Blueprint, jsonify, request, session

from .services import ServiceError, jellyfin

bp = Blueprint("auth", __name__)


@bp.post("/api/login")
def login():
    b = request.get_json(silent=True) or {}
    name, password = str(b.get("username", "")).strip(), str(b.get("password", ""))
    if not name:
        return jsonify(error="Enter your Hevyfin username"), 400
    try:
        r = jellyfin("POST", "/Users/AuthenticateByName", json={"Username": name, "Pw": password})
    except ServiceError as e:
        if e.status in (400, 401):
            return jsonify(error="Wrong username or password"), 401
        raise
    user, token = r["User"], r["AccessToken"]
    if not user.get("Policy", {}).get("IsAdministrator"):
        jellyfin("POST", "/Sessions/Logout", token)
        return jsonify(error=f"{user['Name']} isn't a Hevyfin admin"), 403
    session.clear()
    session.permanent = True
    session.update(token=token, user_id=user["Id"], name=user["Name"])
    return jsonify(id=user["Id"], name=user["Name"])


@bp.post("/api/logout")
def logout():
    try:
        jellyfin("POST", "/Sessions/Logout", session.get("token"))
    except ServiceError:
        pass
    session.clear()
    return jsonify(ok=True)


@bp.get("/api/me")
def me():
    return jsonify(id=session["user_id"], name=session["name"])
