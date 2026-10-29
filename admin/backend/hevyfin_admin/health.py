"""Server health: space, downloads, the VPN behind them, indexers, missing titles; and freeing up
space by deleting films and shows (files too) through Radarr and Sonarr.

Every part is optional. A part whose service isn't set up (no *_URL / *_KEY in the
environment) comes back as {"enabled": false} and the panel leaves its card out. The download
parts (qBittorrent, Prowlarr, release-watch) are off unless you set them up yourself: only
use them for content you have the right to download (see DISCLAIMER.md)."""
import json
import os
from concurrent.futures import ThreadPoolExecutor

from flask import Blueprint, jsonify, session

from .services import ServiceError, jellyfin, prowlarr, qbit, radarr, sonarr

bp = Blueprint("health", __name__)
GB = 1e9
LOW_SPACE_GB = 100
# Written daily by release-watch on the host: releases we're waiting on that the arrs can't spot.
WATCH_FILE = os.environ.get("WATCH_FILE", "/app/watch/watch.json")


@bp.get("/api/health")
def ok():
    return jsonify(ok=True)


def _safe(f):
    try:
        return f()
    except ServiceError as e:
        # 503: the service isn't set up, so this part is simply off.
        return {"enabled": False} if e.status == 503 else {"error": str(e)}


def _space():
    disks = (radarr if radarr.configured else sonarr)("GET", "diskspace")
    # MEDIA_ROOT (e.g. /data) keeps the media disks and hides the system ones.
    root = os.environ.get("MEDIA_ROOT", "")
    out = [{"path": d["path"], "label": d.get("label") or d["path"], "free": d["freeSpace"], "total": d["totalSpace"]}
           for d in disks if not root or d["path"].startswith(root)]
    return out or [{"path": d["path"], "label": d.get("label"), "free": d["freeSpace"], "total": d["totalSpace"]} for d in disks]


def _downloads():
    t = qbit("transfer/info")
    torrents = qbit("torrents/info")
    states = {}
    for x in torrents:
        states[x["state"]] = states.get(x["state"], 0) + 1
    return {"connection": t.get("connection_status"), "down": t.get("dl_info_speed", 0), "up": t.get("up_info_speed", 0),
            "torrents": len(torrents), "errored": [x["name"] for x in torrents if x["state"] in ("error", "missingFiles")][:10],
            "downloading": states.get("downloading", 0), "stalled": states.get("stalledDL", 0)}


def _indexers():
    names = {i["id"]: i["name"] for i in prowlarr("GET", "indexer")}
    off = {s["indexerId"]: s.get("disabledTill") for s in prowlarr("GET", "indexerstatus") if s.get("disabledTill")}
    return [{"name": n, "off": i in off, "until": off.get(i)} for i, n in names.items()]


def _arr(app, missing_path):
    q = app("GET", "queue", params={"pageSize": 500})["records"]
    problems = [{"title": r.get("title"), "status": r.get("trackedDownloadStatus"),
                 "message": "; ".join(m for s in r.get("statusMessages") or [] for m in s.get("messages") or [])[:200]}
                for r in q if r.get("trackedDownloadStatus") in ("warning", "error")]
    return {"queue": len(q), "problems": problems[:15], "missing": app("GET", missing_path, params={"pageSize": 1, "monitored": "true"})["totalRecords"],
            "health": [{"type": h["type"], "message": h["message"]} for h in app("GET", "health")]}


@bp.get("/api/server")
def server():
    with ThreadPoolExecutor(5) as ex:
        f = {k: ex.submit(_safe, v) for k, v in {
            "space": _space, "downloads": _downloads, "indexers": _indexers,
            "sonarr": lambda: _arr(sonarr, "wanted/missing"), "radarr": lambda: _arr(radarr, "wanted/missing")}.items()}
        r = {k: v.result() for k, v in f.items()}
    alerts = []
    for d in r["space"] if isinstance(r["space"], list) else []:
        if d["free"] < LOW_SPACE_GB * GB:
            alerts.append({"level": "bad", "text": f"Only {d['free'] / GB:.0f} GB free on {d['label']}: downloads will start failing"})
    dl = r["downloads"]
    if isinstance(dl, dict) and dl.get("connection") not in (None, "connected"):
        alerts.append({"level": "bad", "text": f"qBittorrent is {dl.get('connection')}: its connection (or the VPN in front of it) may be down"})
    ix = r["indexers"]
    if isinstance(ix, list) and ix and all(i["off"] for i in ix):
        alerts.append({"level": "bad", "text": "All indexers are switched off: nothing new can be found (network or VPN trouble?)"})
    elif isinstance(ix, list) and any(i["off"] for i in ix):
        alerts.append({"level": "warn", "text": "Switched off: " + ", ".join(i["name"] for i in ix if i["off"])})
    for app in ("sonarr", "radarr"):
        a = r[app]
        if isinstance(a, dict) and a.get("enabled") is not False and a.get("problems"):
            alerts.append({"level": "warn", "text": f"{app.title()}: {len(a['problems'])} downloads with problems"})
    for k, v in r.items():
        if isinstance(v, dict) and v.get("error"):
            alerts.append({"level": "bad", "text": v["error"]})
    try:
        watch = json.load(open(WATCH_FILE))
    except (OSError, ValueError):
        watch = None
    for w in (watch or {}).get("watches", []):
        if w["found"]:
            alerts.append({"level": "warn", "text": f"Possibly found: {w['name']} (see On the lookout)"})
    return jsonify(alerts=alerts, watch=watch, **r)


@bp.post("/api/server/indexers/retest")
def retest():
    out = {}
    for name, app in (("prowlarr", prowlarr), ("sonarr", sonarr), ("radarr", radarr)):
        if not app.configured:
            continue
        try:
            res = app("POST", "indexer/testall") or []
            out[name] = sum(1 for x in res if x.get("isValid"))
        except ServiceError as e:
            out[name] = str(e)
    return jsonify(out)


@bp.post("/api/server/search-missing")
def search_missing():
    if sonarr.configured:
        sonarr("POST", "command", json={"name": "MissingEpisodeSearch"})
    if radarr.configured:
        radarr("POST", "command", json={"name": "MissingMoviesSearch"})
    return jsonify(ok=True)


def _watched(kind):
    """Item ids each person has watched (films; for shows: fully watched), by provider id."""
    users = jellyfin("GET", "/Users", session["token"])
    out = {}
    for u in users:
        items = jellyfin("GET", f"/Users/{u['Id']}/Items", session["token"],
                         params={"IncludeItemTypes": kind, "Recursive": "true", "Filters": "IsPlayed", "Fields": "ProviderIds"}).get("Items", [])
        for it in items:
            pid = (it.get("ProviderIds") or {}).get("Tmdb" if kind == "Movie" else "Tvdb")
            if pid:
                out.setdefault(str(pid), []).append(u["Name"])
    return out


@bp.get("/api/library/<kind>")
def library(kind):
    if kind == "movies":
        watched = _watched("Movie")
        items = [{"id": m["id"], "title": m["title"], "year": m.get("year"), "size": m.get("sizeOnDisk", 0), "added": m.get("added"),
                  "watchedBy": watched.get(str(m.get("tmdbId")), [])} for m in radarr("GET", "movie") if m.get("hasFile")]
    elif kind == "shows":
        watched = _watched("Series")
        items = [{"id": s["id"], "title": s["title"], "year": s.get("year"), "size": (s.get("statistics") or {}).get("sizeOnDisk", 0),
                  "added": s.get("added"), "watchedBy": watched.get(str(s.get("tvdbId")), [])}
                 for s in sonarr("GET", "series") if (s.get("statistics") or {}).get("sizeOnDisk")]
    else:
        return jsonify(error="movies or shows"), 400
    items.sort(key=lambda x: -x["size"])
    return jsonify(items[:150])


@bp.delete("/api/library/<kind>/<int:item_id>")
def delete(kind, item_id):
    # Files go too; the exclusion stops import lists from adding it straight back.
    if kind == "movies":
        radarr("DELETE", f"movie/{item_id}", params={"deleteFiles": "true", "addImportExclusion": "true"})
    elif kind == "shows":
        sonarr("DELETE", f"series/{item_id}", params={"deleteFiles": "true", "addImportListExclusion": "true"})
    else:
        return jsonify(error="movies or shows"), 400
    return jsonify(ok=True)
