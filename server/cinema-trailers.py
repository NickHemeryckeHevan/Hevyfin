#!/usr/bin/env python3
"""Daily: keep the trailers of the movies now in cinemas, for Hevyfin's cinema mode and TV channels.

"In cinemas" means released in the last CINEMA_WEEKS weeks (TMDB, through Seerr), most popular
first, up to CINEMA_TOTAL movies. The official trailer of each, as TMDB lists it, is fetched
with yt-dlp (H.264/AAC in MP4, so a Chromecast plays it directly) into CINEMA_DIR/Trailers as
"<Title> (<year>).mp4". Hevyfin's cinema mode plays the videos it finds in that folder. A movie
that drops out of the list has left the cinemas: its trailer is deleted.

Only official trailers linked on TMDB are downloaded, for private viewing on your own server.
You are responsible for following YouTube's and TMDB's terms of use and the law where you live.

Environment:
  CINEMA_DIR        the Cinema folder on this machine (default /media/Cinema)
  SEERR_URL         default http://127.0.0.1:5055
  SEERR_API_KEY     required (Seerr: Settings > General > API key)
  CINEMA_TOTAL      how many movies at most (default 40)
  CINEMA_WEEKS      how far back counts as "in cinemas" (default 8)
  CINEMA_LANGUAGES  original languages to keep, comma-separated ISO 639-1 codes (default en;
                    empty: any)
  CONTAINER         podman (default), docker, or none (yt-dlp from PATH)
  YTDLP_IMAGE       default docker.io/jauderho/yt-dlp:latest
"""
import datetime, json, os, re, subprocess, sys, urllib.request

DIR = os.path.join(os.environ.get("CINEMA_DIR", "/media/Cinema"), "Trailers")
TOTAL = int(os.environ.get("CINEMA_TOTAL", "40"))
WEEKS = int(os.environ.get("CINEMA_WEEKS", "8"))
LANGUAGES = {x.strip() for x in os.environ.get("CINEMA_LANGUAGES", "en").split(",") if x.strip()}
SEERR = os.environ.get("SEERR_URL", "http://127.0.0.1:5055").rstrip("/") + "/api/v1"
KEY = os.environ.get("SEERR_API_KEY") or sys.exit("SEERR_API_KEY is not set (Seerr: Settings > General)")
CONTAINER = os.environ.get("CONTAINER", "podman")
IMAGE = os.environ.get("YTDLP_IMAGE", "docker.io/jauderho/yt-dlp:latest")
FORMAT = "bv*[height<=1080][vcodec^=avc1]+ba[ext=m4a]/b[ext=mp4]"


def seerr(path):
    req = urllib.request.Request(SEERR + path, headers={"X-Api-Key": KEY})
    return json.load(urllib.request.urlopen(req, timeout=60))


def yt_dlp(url, name):
    """Download URL to DIR/NAME; True when it worked."""
    args = ["-q", "--no-playlist", "-f", FORMAT, "--merge-output-format", "mp4"]
    if CONTAINER == "none":
        cmd = ["yt-dlp", *args, "-o", os.path.join(DIR, name), url]
    elif CONTAINER in ("podman", "docker"):
        cmd = [CONTAINER, "run", "--rm", "-v", f"{DIR}:/out:z", IMAGE, *args, "-o", f"/out/{name}", url]
    else:
        sys.exit(f"CONTAINER must be podman, docker or none, not {CONTAINER!r}")
    return subprocess.run(cmd).returncode == 0


def safe(s):
    return re.sub(r'[\\/:*?"<>|]', "", s).strip()


os.makedirs(DIR, exist_ok=True)
today = datetime.date.today()
since = today - datetime.timedelta(weeks=WEEKS)

in_cinemas = []
for page in range(1, 8):
    for m in seerr(f"/discover/movies?page={page}&sortBy=popularity.desc"
                   f"&primaryReleaseDateGte={since}&primaryReleaseDateLte={today}")["results"]:
        if m.get("posterPath") and m.get("voteCount", 0) >= 10 and (not LANGUAGES or m.get("originalLanguage") in LANGUAGES):
            in_cinemas.append(m)

wanted = {}
for m in in_cinemas:
    if len(wanted) >= TOTAL:
        break
    name = f"{safe(m['title'])} ({m['releaseDate'][:4]}).mp4"
    if name in wanted:
        continue
    info = seerr(f"/movie/{m['id']}")
    # Feature films only (TMDB also lists game promos and shorts as "movies").
    if (info.get("runtime") or 0) < 60:
        continue
    vids = [v for v in info.get("relatedVideos", []) if v["site"] == "YouTube" and v["type"] == "Trailer"]
    if not vids:
        continue
    vids.sort(key=lambda v: ("official trailer" not in v["name"].lower(), "teaser" in v["name"].lower()))
    wanted[name] = vids[0]["url"]

for name, url in wanted.items():
    if os.path.exists(os.path.join(DIR, name)):
        continue
    print("downloading", name, url, flush=True)
    if not yt_dlp(url, name):
        print("failed", name, flush=True)

# Left the cinemas (or a download that failed halfway): delete.
for f in os.listdir(DIR):
    p = os.path.join(DIR, f)
    if os.path.isfile(p) and f not in wanted:
        print("removing", f, flush=True)
        os.remove(p)
print("in cinemas:", len(wanted), "· on disk:", len([f for f in os.listdir(DIR) if f.endswith(".mp4")]), flush=True)
