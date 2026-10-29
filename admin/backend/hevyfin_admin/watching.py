"""Now watching: who's streaming what, how, and from where."""
from flask import Blueprint, jsonify, request, session

from .services import jellyfin

bp = Blueprint("watching", __name__)


def J(method, path, **kw):
    return jellyfin(method, path, session["token"], **kw)


@bp.get("/api/sessions")
def sessions():
    out = []
    for s in J("GET", "/Sessions", params={"activeWithinSeconds": 600}):
        if s.get("DeviceId") == "hevyfin-admin-panel":
            continue
        item = s.get("NowPlayingItem")
        ps = s.get("PlayState") or {}
        t = s.get("TranscodingInfo") or {}
        entry = {"id": s["Id"], "user": s.get("UserName"), "device": s.get("DeviceName"), "client": s.get("Client"),
                 "address": s.get("RemoteEndPoint"), "lastActivity": s.get("LastActivityDate"),
                 "canMessage": "DisplayMessage" in (s.get("SupportedCommands") or [])}
        if item:
            dur = item.get("RunTimeTicks") or 0
            entry["playing"] = {
                "title": item.get("Name"), "series": item.get("SeriesName"), "type": item.get("Type"),
                "episode": f"S{item.get('ParentIndexNumber', 0):02d}E{item.get('IndexNumber', 0):02d}" if item.get("Type") == "Episode" else None,
                "itemId": item.get("Id"), "progress": round(100 * (ps.get("PositionTicks") or 0) / dur) if dur else None,
                "paused": ps.get("IsPaused", False), "method": ps.get("PlayMethod"),
                "transcode": t and {"video": t.get("VideoCodec"), "audio": t.get("AudioCodec"), "mbps": round((t.get("Bitrate") or 0) / 1e6, 1),
                                    "hardware": t.get("HardwareAccelerationType"), "reasons": t.get("TranscodeReasons") or []},
            }
        out.append(entry)
    out.sort(key=lambda e: ("playing" not in e, e.get("user") or ""))
    return jsonify(out)


@bp.post("/api/sessions/<sid>/stop")
def stop(sid):
    J("POST", f"/Sessions/{sid}/Playing/Stop")
    return jsonify(ok=True)


@bp.post("/api/sessions/message")
def message():
    b = request.get_json(silent=True) or {}
    text = str(b.get("text", "")).strip()[:300]
    if not text:
        return jsonify(error="Write a message"), 400
    sent = 0
    for s in J("GET", "/Sessions", params={"activeWithinSeconds": 600}):
        if b.get("sessionId") and s["Id"] != b["sessionId"]:
            continue
        if "DisplayMessage" in (s.get("SupportedCommands") or []) and s.get("DeviceId") != "hevyfin-admin-panel":
            J("POST", f"/Sessions/{s['Id']}/Message", json={"Header": "Hevyfin", "Text": text, "TimeoutMs": 15000})
            sent += 1
    return jsonify(sent=sent)
