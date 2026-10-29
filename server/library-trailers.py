#!/usr/bin/env python3
"""Daily: keep a trailer of every film and series in the library, for the Trailer button in Hevyfin.

Jellyfin knows most titles' trailers on YouTube (from TMDB); Seerr fills in the rest (series,
mostly). The official trailer is fetched with yt-dlp (H.264/AAC in MP4, so a Chromecast plays
it directly) into CINEMA_DIR/Library as movie-<tmdb>.mp4 or tv-<tmdb>.mp4, which is how the
app finds it. A title that leaves the library loses its trailer. These are never used as
cinema pre-show trailers (those live in Cinema/Trailers, see cinema-trailers.py). A failed
download is retried after a week. Then Jellyfin is asked to scan its libraries.

Usage: library-trailers.py [LIMIT]   (at most LIMIT downloads this run; default 1000)

Only official trailers linked on TMDB are downloaded, for private viewing on your own server.
You are responsible for following YouTube's and TMDB's terms of use and the law where you live.

Environment:
  CINEMA_DIR        the Cinema folder on this machine (default /media/Cinema)
  JELLYFIN_URL      default http://127.0.0.1:8096
  JELLYFIN_API_KEY  required (Jellyfin: Dashboard > API keys)
  SEERR_URL         default http://127.0.0.1:5055
  SEERR_API_KEY     optional: without it, only the trailers Jellyfin knows are fetched
  STATE_DIR         keeps failed.json (default /var/lib/hevyfin-trailers)
  CONTAINER         podman (default), docker, or none (yt-dlp from PATH)
  YTDLP_IMAGE       default docker.io/jauderho/yt-dlp:latest
"""
import datetime, json, os, subprocess, sys, urllib.request

DIR = os.path.join(os.environ.get("CINEMA_DIR", "/media/Cinema"), "Library")
FAILED = os.path.join(os.environ.get("STATE_DIR", "/var/lib/hevyfin-trailers"), "failed.json")
J = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")
KEY = os.environ.get("JELLYFIN_API_KEY") or sys.exit("JELLYFIN_API_KEY is not set (Jellyfin: Dashboard > API keys)")
SEERR = os.environ.get("SEERR_URL", "http://127.0.0.1:5055").rstrip("/") + "/api/v1"
SEERR_KEY = os.environ.get("SEERR_API_KEY")
CONTAINER = os.environ.get("CONTAINER", "podman")
IMAGE = os.environ.get("YTDLP_IMAGE", "docker.io/jauderho/yt-dlp:latest")
FORMAT = "bv*[height<=1080][vcodec^=avc1]+ba[ext=m4a]/b[ext=mp4]"


def jf(path, method="GET"):
    req = urllib.request.Request(J + path, method=method, headers={"Authorization": f'MediaBrowser Token="{KEY}"'})
    with urllib.request.urlopen(req, timeout=60) as f:
        raw = f.read()
        return json.loads(raw) if raw else None


def seerr_trailers(kind, tmdb):
    if not SEERR_KEY:
        return []
    req = urllib.request.Request(f"{SEERR}/{kind}/{tmdb}", headers={"X-Api-Key": SEERR_KEY})
    try:
        info = json.load(urllib.request.urlopen(req, timeout=60))
    except Exception:
        return []
    return [{"Url": v["url"], "Name": v.get("name")} for v in info.get("relatedVideos", []) if v.get("site") == "YouTube" and v.get("type") == "Trailer"]


def best(trailers):
    yt = [t for t in trailers if "youtube.com/watch" in (t.get("Url") or "") or "youtu.be/" in (t.get("Url") or "")]
    yt.sort(key=lambda t: ("official trailer" not in (t.get("Name") or "").lower(), "teaser" in (t.get("Name") or "").lower()))
    return yt[0]["Url"] if yt else None


def yt_dlp(url, name):
    """Download URL to DIR/NAME; True when it worked."""
    args = ["-q", "--no-playlist", "-f", FORMAT, "--merge-output-format", "mp4"]
    if CONTAINER == "none":
        cmd = ["yt-dlp", *args, "-o", os.path.join(DIR, name), url]
    elif CONTAINER in ("podman", "docker"):
        cmd = [CONTAINER, "run", "--rm", "-v", f"{DIR}:/out:z", IMAGE, *args, "-o", f"/out/{name}", url]
    else:
        sys.exit(f"CONTAINER must be podman, docker or none, not {CONTAINER!r}")
    return subprocess.run(cmd).returncode == 0 and os.path.exists(os.path.join(DIR, name))


os.makedirs(DIR, exist_ok=True)
os.makedirs(os.path.dirname(FAILED), exist_ok=True)
try:
    failed = json.load(open(FAILED))
except Exception:
    failed = {}
today = datetime.date.today()

# collapseBoxSetItems=false, or films in a collection are folded into it.
items = jf("/Items?Recursive=true&IncludeItemTypes=Movie,Series&collapseBoxSetItems=false&Fields=RemoteTrailers,ProviderIds")["Items"]
wanted = {}
for i in items:
    tmdb = (i.get("ProviderIds") or {}).get("Tmdb")
    if not tmdb:
        continue
    kind = "tv" if i["Type"] == "Series" else "movie"
    name = f"{kind}-{tmdb}.mp4"
    url = best(i.get("RemoteTrailers") or [])
    if not url and not os.path.exists(os.path.join(DIR, name)):
        url = best(seerr_trailers(kind, tmdb))
    wanted[name] = (i["Name"], url)

limit = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
changed = 0
for name, (title, url) in wanted.items():
    if not url or os.path.exists(os.path.join(DIR, name)):
        continue
    if name in failed and (today - datetime.date.fromisoformat(failed[name])).days < 7:
        continue
    if limit <= 0:
        break
    limit -= 1
    print("downloading", name, title, url, flush=True)
    if not yt_dlp(url, name):
        print("failed", name, flush=True)
        failed[name] = today.isoformat()
    else:
        failed.pop(name, None)
        changed += 1

# Left the library (or a download that failed halfway): delete.
for f in os.listdir(DIR):
    p = os.path.join(DIR, f)
    if os.path.isfile(p) and f not in wanted:
        print("removing", f, flush=True)
        os.remove(p)
        changed += 1
with open(FAILED, "w") as f:
    json.dump(failed, f)

if changed:
    jf("/Library/Refresh", method="POST")
print("titles:", len(wanted), "· with a trailer online:", len([1 for _, u in wanted.values() if u]), "· on disk:", len([f for f in os.listdir(DIR) if f.endswith(".mp4")]),
      "· failed:", len(failed), flush=True)
