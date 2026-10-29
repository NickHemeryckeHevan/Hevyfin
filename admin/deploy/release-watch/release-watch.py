#!/usr/bin/python3
"""Release watch (optional): looks on your Prowlarr indexers for releases you're waiting on that
Sonarr and Radarr can't recognise themselves, like a particular edition. It never downloads
anything; what it finds is only listed in Hevyfin Admin (Server health > On the lookout).
Only use it for content you have the right to download (see DISCLAIMER.md).

What to look for is in /etc/release-watch.json (example: release-watch.example.json):
  {"watches": [{"id", "name", "query", "match", "exclude", "hint"}]}
  query: the indexer search; match: regex a title must match; exclude: regex that rules it out.
Releases seen on the first run of a watch count as already checked. Run daily by
release-watch.timer; writes $OUT (the folder Hevyfin Admin mounts as /app/watch).

Environment: PROWLARR_URL (default http://127.0.0.1:9696), PROWLARR_KEY (required),
RELEASE_WATCH_CONFIG, RELEASE_WATCH_STATE, RELEASE_WATCH_OUT.
"""
import json
import os
import re
import urllib.parse
import urllib.request
from datetime import datetime, timezone

CONFIG = os.environ.get("RELEASE_WATCH_CONFIG", "/etc/release-watch.json")
STATE = os.environ.get("RELEASE_WATCH_STATE", "/var/lib/release-watch/seen.json")
OUT = os.environ.get("RELEASE_WATCH_OUT", "/srv/hevyfin-admin/watch/watch.json")
PROWLARR = os.environ.get("PROWLARR_URL", "http://127.0.0.1:9696").rstrip("/") + "/api/v1/"
KEEP_DAYS = 90


def search(key, query):
    url = PROWLARR + "search?" + urllib.parse.urlencode({"query": query, "type": "search", "limit": 300})
    return json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"X-Api-Key": key}), timeout=300))


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def main():
    key = os.environ.get("PROWLARR_KEY")
    if not key:
        raise SystemExit("Set PROWLARR_KEY (Prowlarr > Settings > General > API Key)")
    watches = json.load(open(CONFIG))["watches"]
    seen = json.load(open(STATE)) if os.path.exists(STATE) else {}
    now = datetime.now(timezone.utc)
    out = []
    for w in watches:
        state = seen.setdefault(w["id"], {"baseline": None, "found": []})
        entry = {"id": w["id"], "name": w["name"], "hint": w.get("hint", ""), "error": None}
        try:
            results = search(key, w["query"])
        except Exception as e:  # an indexer hiccup shouldn't wipe what was found before
            entry["error"] = f"Search failed: {e}"
            results = None
        if results is not None:
            hits = [r for r in results if re.search(w["match"], r["title"], re.I) and not re.search(w.get("exclude") or "$^", r["title"], re.I)]
            known = {f["title"] for f in state["found"]}
            if state["baseline"] is None:
                state["baseline"] = sorted({r["title"] for r in hits})
            for r in hits:
                if r["title"] in known or r["title"] in state["baseline"]:
                    continue
                known.add(r["title"])
                state["found"].append({"title": r["title"], "size": r["size"], "seeders": r.get("seeders"), "indexer": r["indexer"],
                                       "firstSeen": now.isoformat(timespec="seconds"), "url": r.get("infoUrl")})
            fresh = {r["title"]: r for r in hits}
            for f in state["found"]:  # keep seeders current while it's still listed
                if f["title"] in fresh:
                    f["seeders"] = fresh[f["title"]].get("seeders")
            state["found"] = [f for f in state["found"] if (now - datetime.fromisoformat(f["firstSeen"])).days <= KEEP_DAYS]
        entry["found"] = sorted(state["found"], key=lambda f: f["firstSeen"], reverse=True)
        out.append(entry)
        print(f"{w['name']}: {len(entry['found'])} found" + (f" ({entry['error']})" if entry["error"] else ""))
    write(STATE, seen)
    write(OUT, {"checked": now.isoformat(timespec="seconds"), "watches": out})


if __name__ == "__main__":
    main()
