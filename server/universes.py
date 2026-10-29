#!/usr/bin/env python3
"""Keeps "universe" collections in Jellyfin complete and in story order, for Hevyfin.

A universe is a collection (box set) of films and series that belong together, watched in
the order of the story rather than the order they came out. You describe each one in a JSON
config file (see examples/universes.example.json and docs/custom-collections.md). Run daily
(a systemd timer, cron), for each universe this script:

  1. pulls the current list of its films and series from Wikidata (items that are part of
     its series), so new and announced entries turn up by themselves. Optional;
  2. merges it with the universe's story order from the config. Entries Wikidata knows but
     the config doesn't go at the end, by release date;
  3. adds every entry that is in the library (matched by TMDb id, else by title) to the
     collection, and tags each "story:<universe>:NN" with its place in the story and
     "group:<universe>:<chapter>" with its chapter. The collection gets the "franchise" tag
     plus "missing:"/"upcoming:"/"coming:" tags for what isn't in the library yet. Hevyfin
     shows it with a Release / Story order switch; other Jellyfin apps show release order;
  4. writes the timeline's stops into the collection (provider id "HevyfinStory"). A stop is a
     film, a series, one season of it or a hand-picked cut of episodes, so a series can be
     spread over the story. Titles listed under "drop" are taken out of the collection;
  5. writes each film's measured credits scenes (provider id "HevyfinScenes"), if the config
     has them (see credits-scenes.py).

A custom page design (provider id "HevyfinPage") is never touched: set it by hand or by a
script of your own.

Usage:  universes.py [--config PATH] [--check]
  --config PATH  the universes config (default /etc/hevyfin/universes.json, or $UNIVERSES_CONFIG)
  --check        only read and check the config, then print what's in it (no server needed)

Environment:
  JELLYFIN_URL      default http://127.0.0.1:8096
  JELLYFIN_API_KEY  required (Jellyfin dashboard > API keys)
  CACHE_DIR         Wikidata answers and last-run.txt (default /var/lib/hevyfin-universes)
  ART_DIR           posters for cuts of episodes (default: "art" next to the config file)
  SONARR_URL, SONARR_API_KEY, RADARR_URL, RADARR_API_KEY
                    optional: titles Sonarr/Radarr are still fetching are tagged "coming:"
                    (shown as "On its way"). Skipped when unset.
"""
import argparse
import base64
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

J = os.environ.get("JELLYFIN_URL", "http://127.0.0.1:8096").rstrip("/")
CACHE_DIR = os.environ.get("CACHE_DIR", "/var/lib/hevyfin-universes")
ART_DIR = os.environ.get("ART_DIR")  # set from the config's folder when unset
DEFAULT_CONFIG = os.environ.get("UNIVERSES_CONFIG", "/etc/hevyfin/universes.json")
USER_AGENT = "hevyfin-universes/1.0 (Jellyfin collection sync)"
KINDS = ("movie", "tv")


@dataclass
class Universe:
    name: str
    wikidata: str | tuple  # the Wikidata item(s) of its series; empty: the config's list is the whole universe
    story: list  # [(kind, tmdb, title, part or None)] in story order
    groups: dict = field(default_factory=dict)  # chapter -> {(kind, tmdb)}
    latest: str | None = None  # the chapter for anything new
    skip: set = field(default_factory=set)  # (kind, tmdb) on Wikidata but not part of it
    skip_titles: set = field(default_factory=set)  # normalised titles, likewise
    drop: set = field(default_factory=set)  # (kind, tmdb) once part of it: taken out of the collection
    mini: set = field(default_factory=set)  # tmdb ids of shows whose seasons (and cuts) are each a mini series of their own in the app
    previously: dict = field(default_factory=dict)  # stop title -> what you need to remember from the stops before it
    scenes: dict = field(default_factory=dict)  # film tmdb -> its bonus scenes, for Hevyfin's player

    def group_of(self, kind, tmdb):
        return next((g for g, s in self.groups.items() if (kind, tmdb) in s), self.latest)


# ---- the config ----

class ConfigError(Exception):
    pass


def _ref(x, where):
    """A title reference: "movie:123" or {"kind": "movie", "tmdb": 123}."""
    if isinstance(x, str) and re.fullmatch(r"(movie|tv):\d+", x):
        k, i = x.split(":")
        return k, int(i)
    if isinstance(x, dict) and x.get("kind") in KINDS and isinstance(x.get("tmdb"), int):
        return x["kind"], x["tmdb"]
    raise ConfigError(f'{where}: expected "movie:<tmdb>", "tv:<tmdb>" or {{"kind", "tmdb"}}, got {x!r}')


def _refs(xs, where):
    if not isinstance(xs, list):
        raise ConfigError(f"{where}: expected a list")
    return {_ref(x, f"{where}[{n}]") for n, x in enumerate(xs)}


def _entry(e, where, u):
    """A story entry -> (kind, tmdb, title, part). Inline "group" and "previously" go into
    the universe's chapters and recaps."""
    if not isinstance(e, dict):
        raise ConfigError(f"{where}: expected an object")
    kind, tmdb, title = e.get("kind"), e.get("tmdb"), e.get("title")
    if kind not in KINDS:
        raise ConfigError(f'{where}: "kind" must be "movie" or "tv"')
    if not isinstance(tmdb, int):
        raise ConfigError(f'{where}: "tmdb" must be a number (the TMDb id)')
    if not isinstance(title, str) or not title:
        raise ConfigError(f'{where}: "title" is required (the title as in your library)')
    part = None
    if "season" in e or "episodes" in e:
        if kind != "tv":
            raise ConfigError(f'{where}: "season"/"episodes" only go with "kind": "tv"')
        if "season" in e and "episodes" in e:
            raise ConfigError(f'{where}: give "season" or "episodes", not both')
        if "season" in e:
            if not isinstance(e["season"], int):
                raise ConfigError(f'{where}: "season" must be a number')
            part = {"season": e["season"]}
        else:
            eps = e["episodes"]
            if not (isinstance(eps, list) and eps and all(isinstance(p, list) and len(p) == 2 and all(isinstance(v, int) for v in p) for p in eps)):
                raise ConfigError(f'{where}: "episodes" must be a list of [season, episode] pairs')
            part = {"episodes": [tuple(p) for p in eps]}
        for k in ("stop_title", "art", "group"):
            if k in e:
                part["title" if k == "stop_title" else k] = e[k]
    elif "group" in e:
        u.groups.setdefault(e["group"], set()).add((kind, tmdb))
    elif "stop_title" in e or "art" in e:
        raise ConfigError(f'{where}: "stop_title"/"art" are for a season or a cut of episodes')
    if "previously" in e:
        u.previously[(part or {}).get("title") or title] = e["previously"]
    return kind, tmdb, title, part


def _universe(c, where):
    if not isinstance(c, dict) or not isinstance(c.get("name"), str) or not c["name"]:
        raise ConfigError(f'{where}: every universe needs a "name" (the collection\'s name in Jellyfin)')
    where = f"universe {c['name']!r}"
    known = {"name", "wikidata", "story", "groups", "chapters", "latest", "skip", "skip_titles", "drop", "mini", "previously", "scenes"}
    unknown = [k for k in c if k not in known and not k.startswith("_")]
    if unknown:
        raise ConfigError(f"{where}: unknown keys {unknown} (keys starting with _ are comments)")
    wd = c.get("wikidata", ())
    wd = (wd,) if isinstance(wd, str) else tuple(wd)
    if not all(isinstance(q, str) and re.fullmatch(r"Q\d+", q) for q in wd):
        raise ConfigError(f'{where}: "wikidata" must be a Wikidata id like "Q12345", or a list of them')
    u = Universe(c["name"], wd, [], latest=c.get("latest"))
    groups = c.get("groups", c.get("chapters", {}))
    if not isinstance(groups, dict):
        raise ConfigError(f'{where}: "groups" must map a chapter name to a list of titles')
    for g, xs in groups.items():
        u.groups.setdefault(g, set()).update(_refs(xs, f"{where}, groups[{g!r}]"))
    if not isinstance(c.get("story", []), list):
        raise ConfigError(f'{where}: "story" must be a list')
    u.story = [_entry(e, f"{where}, story[{n}]", u) for n, e in enumerate(c.get("story", []))]
    u.skip = _refs(c.get("skip", []), f"{where}, skip")
    u.drop = _refs(c.get("drop", []), f"{where}, drop")
    u.skip_titles = {norm(t) for t in c.get("skip_titles", [])}
    mini = c.get("mini", [])
    if not (isinstance(mini, list) and all(isinstance(i, int) for i in mini)):
        raise ConfigError(f'{where}: "mini" must be a list of TMDb ids of series')
    u.mini = set(mini)
    prev = c.get("previously", {})
    if not isinstance(prev, dict):
        raise ConfigError(f'{where}: "previously" must map a stop title to its text')
    u.previously.update({k: v for k, v in prev.items() if not k.startswith("_")})
    for k, v in (c.get("scenes") or {}).items():
        if k.startswith("_"):
            continue
        w = f"{where}, scenes[{k!r}]"
        if not k.isdigit() or not isinstance(v, dict) or not all(isinstance(v.get(x), (int, float)) for x in ("runtime", "credits")):
            raise ConfigError(f'{w}: expected "<film tmdb>": {{"runtime": s, "credits": s, "scenes": [...]}}')
        for s in v.get("scenes", []):
            if not (isinstance(s, dict) and isinstance(s.get("start"), (int, float)) and isinstance(s.get("end"), (int, float))
                    and s.get("kind") in ("mid", "post")):
                raise ConfigError(f'{w}: each scene is {{"start": s, "end": s, "kind": "mid"|"post"[, "spoiler": true]}}')
        u.scenes[int(k)] = v
    if not u.story and not u.wikidata:
        raise ConfigError(f'{where}: give a "story" list, a "wikidata" id, or both')
    return u


def load_config(path):
    """The universes in the JSON file at PATH: a list of universes, or {"universes": [...]}."""
    global ART_DIR
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"no config at {path} (see examples/universes.example.json; --config PATH)")
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path} is not valid JSON: {e}")
    if isinstance(data, dict):
        data = data.get("universes")
    if not isinstance(data, list):
        raise ConfigError(f'{path}: expected a list of universes, or {{"universes": [...]}}')
    if ART_DIR is None:
        ART_DIR = os.path.join(os.path.dirname(os.path.abspath(path)), "art")
    return [_universe(c, f"universes[{n}]") for n, c in enumerate(data)]


# ---- Wikidata ----

QUERY = """
SELECT DISTINCT ?item ?itemLabel ?tmdbMovie ?tmdbTv ?date WHERE {
  { ?item wdt:P179+ wd:%s } UNION { ?item wdt:P361+ wd:%s }
  { ?item wdt:P4947 ?tmdbMovie } UNION { ?item wdt:P4983 ?tmdbTv }
  OPTIONAL { ?item wdt:P577 ?date }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}"""


def norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def wikidata(qid):
    """[(kind, tmdb, title, date)] from Wikidata; the last good answer if it's unreachable."""
    cache = f"{CACHE_DIR}/{qid}.json"
    try:
        url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": QUERY % (qid, qid)})
        r = urllib.request.Request(url, headers={"Accept": "application/sparql-results+json", "User-Agent": USER_AGENT})
        rows = json.load(urllib.request.urlopen(r, timeout=60))["results"]["bindings"]
        out = {}
        for b in rows:
            m, t = b.get("tmdbMovie", {}).get("value"), b.get("tmdbTv", {}).get("value")
            k = ("movie", int(m)) if m and m.isdigit() else (("tv", int(t)) if t and t.isdigit() else None)
            if k is None:
                continue
            d = b.get("date", {}).get("value", "")[:10]
            if k not in out or (d and d < (out[k][1] or "9")):
                out[k] = (b["itemLabel"]["value"], d)
        found = [(k[0], k[1], v[0], v[1]) for k, v in out.items()]
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(cache, "w") as f:
            json.dump(found, f)
        return found
    except Exception as e:
        print(f"wikidata unreachable ({e}); using the last list")
        try:
            return [tuple(x) for x in json.load(open(cache))]
        except Exception:
            return []


# ---- Jellyfin ----

def key():
    k = os.environ.get("JELLYFIN_API_KEY")
    if not k:
        sys.exit("JELLYFIN_API_KEY is not set (make one in Jellyfin: Dashboard > API keys)")
    return k


def req(method, path, body=None, **q):
    url = J + path + ("?" + urllib.parse.urlencode(q) if q else "")
    h = {"Authorization": f'MediaBrowser Token="{key()}"'}
    data = None
    if body is not None:
        data, h["Content-Type"] = json.dumps(body).encode(), "application/json"
    with urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers=h), timeout=60) as f:
        raw = f.read()
        return json.loads(raw) if raw else None


def admin_user():
    """An administrator's user id: items are read as a user, who sees every library."""
    return next(u["Id"] for u in req("GET", "/Users") if u["Policy"]["IsAdministrator"])


def art(name, ep, uid):
    """A cut's poster, kept on its first episode as a "Box" image (no app shows those for an
    episode). Uploaded when that episode hasn't got one: a new copy of it is a new item. To swap
    a poster, change the file and delete the episode's Box image."""
    tag = (ep.get("ImageTags") or {}).get("Box")
    if not tag:
        path = os.path.join(ART_DIR or ".", name)
        if not os.path.exists(path):
            print(f"poster {path} not found; the cut shows its show's poster")
            return None
        mime = "image/png" if path.lower().endswith(".png") else "image/jpeg"
        r = urllib.request.Request(f"{J}/Items/{ep['Id']}/Images/Box", data=base64.b64encode(open(path, "rb").read()), method="POST",
                                   headers={"Authorization": f'MediaBrowser Token="{key()}"', "Content-Type": mime})
        urllib.request.urlopen(r, timeout=60).read()
        tag = (req("GET", f"/Items/{ep['Id']}", userId=uid).get("ImageTags") or {}).get("Box")
        print(f"poster {name} on {ep.get('SeriesName', '')} S{ep.get('ParentIndexNumber')}E{ep.get('IndexNumber')}")
    return {"id": ep["Id"], "tag": tag} if tag else None


def code(part):
    """How a part of a series is labelled under its stop: "Season 2", "S1 · E16–17"."""
    if "season" in part:
        return f"Season {part['season']}"
    eps = part["episodes"]
    if len({s for s, _ in eps}) > 1:
        return ", ".join(f"S{s}E{e}" for s, e in eps)
    n = [e for _, e in eps]
    run = n == list(range(n[0], n[-1] + 1))
    return f"S{eps[0][0]} · " + (f"E{n[0]}" if len(n) == 1 else f"E{n[0]}–{n[-1]}" if run else ", ".join(f"E{e}" for e in n))


def getting():
    """(kind, tmdb) that Sonarr/Radarr are fetching: monitored, with files still to come.
    Seerr misses shows wanted by the episode (no whole season monitored), so the page asks
    here. Only for the apps whose URL and API key are set."""
    out = set()
    for app in ("sonarr", "radarr"):
        url, k = os.environ.get(f"{app.upper()}_URL"), os.environ.get(f"{app.upper()}_API_KEY")
        if not (url and k):
            continue
        try:
            r = urllib.request.Request(f"{url.rstrip('/')}/api/v3/{'series' if app == 'sonarr' else 'movie'}", headers={"X-Api-Key": k})
            for x in json.load(urllib.request.urlopen(r, timeout=60)):
                if app == "radarr" and x["monitored"] and not x["hasFile"]:
                    out.add(("movie", x["tmdbId"]))
                st = x.get("statistics") or {}
                if app == "sonarr" and x["monitored"] and st.get("episodeCount", 0) > st.get("episodeFileCount", 0):
                    out.add(("tv", x["tmdbId"]))
        except Exception as e:
            print(f"{app} unreachable ({e}); nothing marked as coming from it")
    return out


def sync(u, uid, lib, coming=frozenset()):
    NAME, TAG = u.name, f"story:{u.name}:"
    story = list(u.story)
    # The full list in story order: the story list first, then anything newer Wikidata knows about.
    known = {(k, i) for k, i, _, _ in story}
    wd = [x for q in u.wikidata for x in wikidata(q)]
    extra = sorted(
        (x for x in wd if (x[0], x[1]) not in known | u.skip | u.drop and norm(x[2]) not in u.skip_titles),
        key=lambda x: x[3] or "9999",
    )
    order = story + [(k, i, t, None) for k, i, t, _ in extra]
    dates = {(k, i): d for k, i, _, d in wd}
    if extra:
        print(f"{NAME}: new on Wikidata (after the known story):", ", ".join(t for _, _, t, _ in extra))

    by_id = {("movie" if i["Type"] == "Movie" else "tv", (i.get("ProviderIds") or {}).get("Tmdb")): i for i in lib}
    by_name = {("movie" if i["Type"] == "Movie" else "tv", norm(i["Name"])): i for i in lib}
    members = {}  # library item id -> (its first story place, item, chapter)
    stops = []  # the timeline Hevyfin shows: whole titles, seasons and cuts, in story order
    absent = []  # (kind, tmdb, date) not in the library
    episodes = {}  # series id -> its episodes in the library
    for n, (kind, tmdb, title, part) in enumerate(order, 1):
        chapter = (part or {}).get("group") or u.group_of(kind, tmdb)
        recap = u.previously.get((part or {}).get("title") or title)
        item = by_id.get((kind, str(tmdb))) or by_name.get((kind, norm(title)))
        if not item:
            absent.append((kind, tmdb, dates.get((kind, tmdb)) or ""))
            continue
        if part:
            if item["Id"] not in episodes:
                episodes[item["Id"]] = [e for e in req("GET", f"/Shows/{item['Id']}/Episodes", userId=uid)["Items"]
                                        if e.get("LocationType") != "Virtual"]
            want = part.get("episodes")
            eps = [e for e in episodes[item["Id"]]
                   if (e.get("ParentIndexNumber"), e.get("IndexNumber")) in want] if want else \
                  [e for e in episodes[item["Id"]] if e.get("ParentIndexNumber") == part["season"]]
            if not eps:  # that part isn't downloaded yet
                absent.append((kind, tmdb, dates.get((kind, tmdb)) or ""))
                continue
            stop = {"kind": "cut" if want else "season", "ids": [e["Id"] for e in eps], "series": item["Id"],
                    "season": eps[0].get("ParentIndexNumber"), "title": part.get("title") or item["Name"], "code": code(part),
                    "date": min((e.get("PremiereDate") or "")[:10] for e in eps)}
            if part.get("art") and (poster := art(part["art"], eps[0], uid)):
                stop["art"] = poster
            if tmdb in u.mini:
                stop["mini"] = True
        else:
            stop = {"kind": "movie" if item["Type"] == "Movie" else "series", "ids": [item["Id"]], "title": item["Name"],
                    "date": (item.get("PremiereDate") or "")[:10]}
        if chapter:
            stop["group"] = chapter
        if recap:
            stop["previously"] = recap
        stops.append(stop)
        members.setdefault(item["Id"], (n, item, chapter))
    members = list(members.values())

    sets = req("GET", "/Items", userId=uid, recursive="true", includeItemTypes="BoxSet", searchTerm=NAME)["Items"]
    box = next((b for b in sets if b["Name"] == NAME), None)
    if box is None:
        if not members:
            return print(f"{NAME}: nothing in the library yet")
        box = req("POST", "/Collections", name=NAME, ids=",".join(i["Id"] for _, i, _ in members))
        print(f"created {NAME}")
    inside = req("GET", "/Items", userId=uid, parentId=box["Id"], fields="ProviderIds,Tags")["Items"]
    have = {m["Id"] for m in inside}
    new = [i for _, i, _ in members if i["Id"] not in have]
    if new:
        req("POST", f"/Collections/{box['Id']}/Items", ids=",".join(i["Id"] for i in new))
        print("added:", ", ".join(i["Name"] for i in new))
    # Dropped titles, and those this job once placed on the path that are no longer on it:
    # Hevyfin would list them after the story.
    placed = {i["Id"] for _, i, _ in members}
    gone = [m for m in inside if ("movie" if m["Type"] == "Movie" else "tv", int((m.get("ProviderIds") or {}).get("Tmdb") or 0)) in u.drop
            or (m["Id"] not in placed and any(t.startswith(TAG) for t in m.get("Tags") or []))]
    if gone:
        req("DELETE", f"/Collections/{box['Id']}/Items", ids=",".join(m["Id"] for m in gone))
        print("removed:", ", ".join(m["Name"] for m in gone))

    # Each title's place in the story and its chapter, as tags, and a film's bonus scenes (for
    # Hevyfin's player, "HevyfinScenes"); only changed items are rewritten.
    group = f"group:{NAME}:"
    retagged = 0
    for n, item, chapter in members + [(0, m, None) for m in gone]:
        want = ([f"{TAG}{n:02d}"] + ([f"{group}{chapter}"] if chapter else [])) if n else []
        full = req("GET", f"/Items/{item['Id']}", userId=uid) if n == 0 else None
        tags = (full or item).get("Tags") or []
        mine = sorted(t for t in tags if t.startswith((TAG, group)))
        scenes = u.scenes.get(int((item.get("ProviderIds") or {}).get("Tmdb") or 0)) if n and item["Type"] == "Movie" else None
        # The times are the measured file's: a film whose file has changed since loses them.
        if scenes and abs((item.get("RunTimeTicks") or 0) / 1e7 - scenes["runtime"]) > 2:
            print(f"{item['Name']}: its file changed since its bonus scenes were measured; run credits-scenes.py again")
            scenes = None
        told = json.dumps({k: scenes[k] for k in ("credits", "scenes")}, separators=(",", ":")) if scenes else None
        if mine == sorted(want) and ((full or item).get("ProviderIds") or {}).get("HevyfinScenes") == told:
            continue
        full = full or req("GET", f"/Items/{item['Id']}", userId=uid)
        # Read-only parts Jellyfin can't take back (its scrub-preview table breaks the update).
        for k in ("Trickplay", "MediaSources", "MediaStreams", "Chapters", "UserData"):
            full.pop(k, None)
        full["Tags"] = [t for t in (full.get("Tags") or []) if not t.startswith((TAG, group))] + want
        full["ProviderIds"] = {k: v for k, v in (full.get("ProviderIds") or {}).items() if k != "HevyfinScenes"} | ({"HevyfinScenes": told} if told else {})
        req("POST", f"/Items/{item['Id']}", body=full)
        retagged += 1

    # For Hevyfin: what's not in the library yet ("missing:<kind>:<tmdb>" for released titles,
    # "upcoming:<kind>:<tmdb>:<date>" for the rest). A custom page design (in the collection's
    # provider ids, "HevyfinPage") is never touched here. Release order in other Jellyfin apps.
    today = datetime.date.today().isoformat()
    meta = {"franchise"}
    for kind, tmdb, d in absent:
        d = d if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d or "") else ""
        if d > today or (not d and (kind, tmdb) not in known):
            meta.add(f"upcoming:{kind}:{tmdb}:{d}")  # no date: announced, not dated yet
        else:
            meta.add(f"missing:{kind}:{tmdb}")
            if (kind, tmdb) in coming:  # already being downloaded: "On its way" in Hevyfin
                meta.add(f"coming:{kind}:{tmdb}")
    # The timeline's stops (seasons and cuts of a series too) go in the provider ids next to the
    # page's design ("HevyfinStory"); Hevyfin falls back to one stop per title without it.
    b = req("GET", f"/Items/{box['Id']}", userId=uid)
    kept = {t for t in (b.get("Tags") or []) if not t.startswith(("missing:", "upcoming:", "coming:"))} | meta
    told = json.dumps(stops, ensure_ascii=False, separators=(",", ":"))
    ids = b.get("ProviderIds") or {}
    if b.get("DisplayOrder") != "PremiereDate" or set(b.get("Tags") or []) != kept or ids.get("HevyfinStory") != told:
        for k in ("Trickplay", "MediaSources", "MediaStreams", "Chapters", "UserData"):
            b.pop(k, None)
        b["DisplayOrder"] = "PremiereDate"
        b["Tags"] = sorted(kept)
        b["ProviderIds"] = {**ids, "HevyfinStory": told}
        b["LockData"] = True  # keep it as set, also through metadata refreshes
        req("POST", f"/Items/{box['Id']}", body=b)
    print(f"{NAME}: {len(members)} titles in {len(stops)} stops, {len(new)} added, {len(gone)} removed, "
          f"{retagged} retagged; {len(order)} on the full list")


class Log:
    """Also keeps the run's output in CACHE_DIR/last-run.txt, to read after a timer ran it."""

    def __init__(self, out):
        self.out, self.lines = out, []

    def write(self, s):
        self.lines.append(s)
        return self.out.write(s)

    def flush(self):
        self.out.flush()


def check(universes):
    for u in universes:
        parts = sum(1 for e in u.story if e[3])
        print(f"{u.name}: {len(u.story)} story entries ({parts} seasons or cuts), {len(u.groups)} chapters, "
              f"wikidata {', '.join(u.wikidata) or 'none'}, {len(u.previously)} recaps, {len(u.scenes)} with credits scenes")
    print(f"config OK; cut posters are read from {ART_DIR}")


def main():
    p = argparse.ArgumentParser(description="Keep universe collections in Jellyfin complete and in story order, for Hevyfin.")
    p.add_argument("--config", default=DEFAULT_CONFIG, help=f"the universes config (default {DEFAULT_CONFIG})")
    p.add_argument("--check", action="store_true", help="only check the config and print what's in it")
    a = p.parse_args()
    try:
        universes = load_config(a.config)
    except ConfigError as e:
        sys.exit(f"config: {e}")
    if a.check:
        return check(universes)
    key()  # fail early without a key
    sys.stdout = log = Log(sys.stdout)
    try:
        run(universes)
    finally:
        sys.stdout = log.out
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(f"{CACHE_DIR}/last-run.txt", "w") as f:
                f.write(f"Run {datetime.datetime.now():%Y-%m-%d %H:%M}\n" + "".join(log.lines))
        except OSError as e:
            print(f"couldn't write {CACHE_DIR}/last-run.txt ({e}); set CACHE_DIR")


def run(universes):
    # As a user, with films not folded into their collections.
    uid = admin_user()
    lib = req("GET", "/Items", userId=uid, recursive="true", includeItemTypes="Movie,Series",
              collapseBoxSetItems="false", fields="ProviderIds,Tags,PremiereDate")["Items"]
    coming = getting()
    for u in universes:
        try:
            sync(u, uid, lib, coming)
        except Exception as e:  # one universe failing mustn't stop the others
            print(f"{u.name}: failed: {e}")


if __name__ == "__main__":
    main()
