"""People: everyone's Hevyfin account and request rights."""
from flask import Blueprint, jsonify, request, session

from .services import ServiceError, jellyfin, seerr

bp = Blueprint("people", __name__)
REQUEST, AUTO_APPROVE, ADMIN = 32, 128, 2  # Seerr permission bits


def J(method, path, **kw):
    return jellyfin(method, path, session["token"], **kw)


def _seerr_users():
    try:
        return {u.get("jellyfinUserId"): u for u in seerr("GET", "user", params={"take": 200})["results"]}
    except ServiceError:
        return {}


def _person(u, devices, su):
    p = u.get("Policy", {})
    s = su.get(u["Id"])
    return {
        "id": u["Id"], "name": u["Name"], "admin": p.get("IsAdministrator", False), "disabled": p.get("IsDisabled", False),
        "lastActivity": u.get("LastActivityDate"), "lastLogin": u.get("LastLoginDate"), "hasPassword": u.get("HasPassword", True),
        "maxParentalRating": p.get("MaxParentalRating"), "allLibraries": p.get("EnableAllFolders", True),
        "libraries": p.get("EnabledFolders", []), "remoteBitrate": p.get("RemoteClientBitrateLimit", 0),
        "schedules": p.get("AccessSchedules", []), "devices": devices.get(u["Id"], 0),
        "seerr": s and {
            "id": s["id"], "admin": bool(s["permissions"] & ADMIN), "canRequest": bool(s["permissions"] & (REQUEST | ADMIN)),
            "autoApprove": bool(s["permissions"] & (AUTO_APPROVE | ADMIN)), "requests": s.get("requestCount", 0),
            "movieQuota": {"limit": s.get("movieQuotaLimit"), "days": s.get("movieQuotaDays")},
            "tvQuota": {"limit": s.get("tvQuotaLimit"), "days": s.get("tvQuotaDays")},
        },
    }


@bp.get("/api/people")
def people():
    users = J("GET", "/Users")
    devices = {}
    for d in (J("GET", "/Devices") or {}).get("Items", []):
        devices[d.get("LastUserId")] = devices.get(d.get("LastUserId"), 0) + 1
    su = _seerr_users()
    libs = [{"id": l["ItemId"], "name": l["Name"]} for l in J("GET", "/Library/VirtualFolders")]
    ratings = [{"name": r["Name"], "value": r["Value"]} for r in J("GET", "/Localization/ParentalRatings") if r.get("Value") is not None]
    seen, uniq = set(), []
    for r in sorted(ratings, key=lambda r: r["value"]):
        if r["value"] not in seen:
            seen.add(r["value"]); uniq.append(r)
    return jsonify(people=[_person(u, devices, su) for u in sorted(users, key=lambda u: (not u["Policy"]["IsAdministrator"], u["Name"].lower()))],
                   libraries=libs, ratings=uniq, me=session["user_id"])


@bp.post("/api/people")
def add_person():
    b = request.get_json(silent=True) or {}
    name, password = str(b.get("name", "")).strip(), str(b.get("password", ""))
    if not name or len(password) < 4:
        return jsonify(error="Give a name and a password of at least 4 characters"), 400
    u = J("POST", "/Users/New", json={"Name": name, "Password": password})
    try:  # their Seerr account, so they can request from day one
        seerr("POST", "user/import-from-jellyfin", json={"jellyfinUserIds": [u["Id"]]})
    except ServiceError:
        pass
    return jsonify(id=u["Id"], name=u["Name"])


@bp.post("/api/people/<uid>/password")
def password(uid):
    b = request.get_json(silent=True) or {}
    new = str(b.get("password", ""))
    if len(new) < 4:
        return jsonify(error="Use at least 4 characters"), 400
    body = {"NewPw": new}
    if uid == session["user_id"]:  # Jellyfin wants your current password for your own account
        body["CurrentPw"] = str(b.get("current", ""))
    try:
        J("POST", f"/Users/{uid}/Password", json=body)
    except ServiceError as e:
        if e.status in (400, 401, 403):
            return jsonify(error="Jellyfin refused it" + (": check your current password" if uid == session["user_id"] else "")), 400
        raise
    signed_out = _sign_out(uid) if b.get("signOut") else 0
    return jsonify(ok=True, signedOut=signed_out)


def _devices(uid):
    """Their devices. Jellyfin ignores ?userId= on /Devices and returns everyone's, so match on
    the device's last signed-in user here."""
    return [d for d in (J("GET", "/Devices") or {}).get("Items", []) if d.get("LastUserId") == uid]


def _sign_out(uid, only=None):
    """Removes their devices, which ends those sign-ins (never the panel's own, never anyone else's)."""
    n = 0
    for d in _devices(uid):
        if d["Id"] == "hevyfin-admin-panel" or (only and d["Id"] != only) or d.get("LastUserId") != uid:
            continue
        J("DELETE", "/Devices", params={"id": d["Id"]})
        n += 1
    return n


@bp.get("/api/people/<uid>/devices")
def devices(uid):
    items = sorted(_devices(uid), key=lambda d: d.get("DateLastActivity") or "", reverse=True)
    return jsonify([{"id": d["Id"], "name": d.get("Name"), "app": f"{d.get('AppName', '')} {d.get('AppVersion', '')}".strip(),
                     "lastSeen": d.get("DateLastActivity"), "panel": d["Id"] == "hevyfin-admin-panel"} for d in items])


@bp.delete("/api/people/<uid>/devices/<did>")
def remove_device(uid, did):
    return jsonify(signedOut=_sign_out(uid, only=did))


@bp.post("/api/people/<uid>/signout")
def sign_out_all(uid):
    return jsonify(signedOut=_sign_out(uid))


@bp.put("/api/people/<uid>/policy")
def policy(uid):
    b = request.get_json(silent=True) or {}
    p = J("GET", f"/Users/{uid}")["Policy"]
    if uid == session["user_id"] and (b.get("disabled") or b.get("admin") is False):
        return jsonify(error="You can't switch off or demote your own account here"), 400
    if "disabled" in b:
        p["IsDisabled"] = bool(b["disabled"])
    if "admin" in b:
        p["IsAdministrator"] = bool(b["admin"])
    if "maxParentalRating" in b:
        p["MaxParentalRating"] = b["maxParentalRating"]
    if "allLibraries" in b:
        p["EnableAllFolders"] = bool(b["allLibraries"])
    if "libraries" in b:
        p["EnabledFolders"] = list(b["libraries"])
    if "remoteBitrateMbps" in b:
        p["RemoteClientBitrateLimit"] = int(float(b["remoteBitrateMbps"] or 0) * 1_000_000)
    if "schedules" in b:  # [{DayOfWeek: "Everyday"|"Weekday"|"Weekend"|"Monday"…, StartHour: 7, EndHour: 21}]
        p["AccessSchedules"] = [{"DayOfWeek": s["DayOfWeek"], "StartHour": float(s["StartHour"]), "EndHour": float(s["EndHour"])} for s in b["schedules"]]
    J("POST", f"/Users/{uid}/Policy", json=p)
    return jsonify(ok=True)


@bp.put("/api/people/<uid>/requests")
def request_rights(uid):
    b = request.get_json(silent=True) or {}
    s = _seerr_users().get(uid)
    if not s:
        seerr("POST", "user/import-from-jellyfin", json={"jellyfinUserIds": [uid]})
        s = _seerr_users().get(uid)
    if not s:
        return jsonify(error="No Seerr account for them"), 400
    perms = s["permissions"]
    if not perms & ADMIN:
        if "canRequest" in b:
            perms = perms | REQUEST if b["canRequest"] else perms & ~REQUEST
        if "autoApprove" in b:
            perms = perms | AUTO_APPROVE if b["autoApprove"] else perms & ~AUTO_APPROVE
        seerr("POST", f"user/{s['id']}/settings/permissions", json={"permissions": perms})
    main = seerr("GET", f"user/{s['id']}/settings/main")
    for kind in ("movie", "tv"):
        q = b.get(f"{kind}Quota")
        if q is not None:
            main[f"{kind}QuotaLimit"] = int(q["limit"]) if q.get("limit") else None
            main[f"{kind}QuotaDays"] = int(q["days"]) if q.get("days") else None
    seerr("POST", f"user/{s['id']}/settings/main", json=main)
    return jsonify(ok=True)
