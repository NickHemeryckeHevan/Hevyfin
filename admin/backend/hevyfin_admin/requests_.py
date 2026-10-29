"""Requests: what people asked for in Hevyfin (Seerr), to approve or decline, and asking on
someone's behalf."""
import time
import urllib.parse

from flask import Blueprint, jsonify, request

from .services import ServiceError, seerr

bp = Blueprint("requests", __name__)
STATUS = {1: "pending", 2: "approved", 3: "declined", 4: "failed", 5: "completed"}
MEDIA = {1: "unknown", 2: "pending", 3: "downloading", 4: "partly available", 5: "available", 6: "deleted"}
_titles = {}


def _title(kind, tmdb):
    key = (kind, tmdb)
    hit = _titles.get(key)
    if hit and time.time() - hit[0] < 86400:
        return hit[1]
    try:
        d = seerr("GET", f"{kind}/{tmdb}")
        info = {"title": d.get("title") or d.get("name"), "year": (d.get("releaseDate") or d.get("firstAirDate") or "")[:4],
                "poster": f"https://image.tmdb.org/t/p/w185{d['posterPath']}" if d.get("posterPath") else None}
    except ServiceError:
        info = {"title": f"TMDB {tmdb}", "year": "", "poster": None}
    _titles[key] = (time.time(), info)
    return info


@bp.get("/api/requests")
def list_requests():
    f = request.args.get("filter", "pending")
    r = seerr("GET", "request", params={"take": 60, "skip": 0, "filter": f, "sort": "added"})
    out = []
    for x in r["results"]:
        m = x["media"]
        kind = x["type"]
        info = _title(kind, m["tmdbId"])
        out.append({"id": x["id"], "type": kind, **info, "status": STATUS.get(x["status"], x["status"]),
                    "media": MEDIA.get(m.get("status"), ""), "by": (x.get("requestedBy") or {}).get("displayName"),
                    "byId": (x.get("requestedBy") or {}).get("id"), "at": x["createdAt"],
                    "seasons": [s["seasonNumber"] for s in x.get("seasons") or []],
                    "decidedBy": (x.get("modifiedBy") or {}).get("displayName") if x["status"] in (2, 3) else None})
    counts = seerr("GET", "request/count")
    return jsonify(requests=out, counts=counts)


@bp.post("/api/requests/<int:rid>/<action>")
def decide(rid, action):
    if action not in ("approve", "decline"):
        return jsonify(error="approve or decline"), 400
    seerr("POST", f"request/{rid}/{action}")
    return jsonify(ok=True)


@bp.get("/api/search")
def search():
    q = request.args.get("q", "").strip()
    if not q:
        return jsonify([])
    # Seerr wants %20 for spaces, not +.
    r = seerr("GET", "search?query=" + urllib.parse.quote(q) + "&page=1")
    out = []
    for x in r["results"]:
        if x.get("mediaType") not in ("movie", "tv"):
            continue
        out.append({"id": x["id"], "type": x["mediaType"], "title": x.get("title") or x.get("name"),
                    "year": (x.get("releaseDate") or x.get("firstAirDate") or "")[:4],
                    "poster": f"https://image.tmdb.org/t/p/w185{x['posterPath']}" if x.get("posterPath") else None,
                    "status": MEDIA.get((x.get("mediaInfo") or {}).get("status"), "")})
    return jsonify(out[:20])


@bp.post("/api/requests")
def request_for():
    b = request.get_json(silent=True) or {}
    body = {"mediaType": b.get("type"), "mediaId": int(b.get("id")), "userId": int(b["userId"]) if b.get("userId") else None}
    if body["mediaType"] == "tv":
        body["seasons"] = b.get("seasons") or "all"
    r = seerr("POST", "request", json={k: v for k, v in body.items() if v is not None})
    return jsonify(id=r["id"])
