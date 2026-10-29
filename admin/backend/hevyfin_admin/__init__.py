"""Hevyfin Admin: your server's accounts, requests, who's watching and the server's health,
in one panel for Hevyfin's admins. Sign in with a Hevyfin (Jellyfin) admin account."""
import os

from flask import Flask, jsonify, request, send_from_directory, session

from .services import ServiceError


def create_app():
    app = Flask(__name__, static_folder=None)
    app.secret_key = os.environ["SECRET_KEY"]
    app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Strict", PERMANENT_SESSION_LIFETIME=60 * 60 * 12)

    from . import auth, health, people, requests_, watching
    for bp in (auth.bp, people.bp, requests_.bp, watching.bp, health.bp):
        app.register_blueprint(bp)

    @app.before_request
    def guard():
        if not request.path.startswith("/api/") or request.path in ("/api/login", "/api/health"):
            return None
        if not session.get("token"):
            return jsonify(error="Sign in first"), 401
        # Changes only from the panel itself (its requests carry this header; other sites can't add it).
        if request.method != "GET" and request.headers.get("X-Hevyfin-Admin") != "1":
            return jsonify(error="Not allowed"), 403
        return None

    @app.errorhandler(ServiceError)
    def service_error(e):
        if e.status == 401 and request.path != "/api/login":
            session.clear()
            return jsonify(error="Signed out: sign in again"), 401
        return jsonify(error=str(e)), e.status

    static = os.environ.get("STATIC_DIR", os.path.join(os.path.dirname(__file__), "..", "..", "frontend", "dist"))

    @app.get("/")
    @app.get("/<path:path>")
    def page(path="index.html"):
        if path.startswith("api/"):
            return jsonify(error="Not found"), 404
        full = os.path.join(static, path)
        return send_from_directory(static, path if os.path.isfile(full) else "index.html")

    return app
