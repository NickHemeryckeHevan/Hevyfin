#!/usr/bin/env python3
"""Helps you find the bonus scenes in films' credits (mid- and post-credits), for the "scenes"
of a universe in universes.py's config. Hevyfin's player then offers to skip the credits
but not the scenes. It's done by hand, with some help:

  sheets   a contact sheet per film: its credits (from BEFORE seconds ahead of them), a frame
           every STEP seconds, left to right, top to bottom, in OUT/<tmdb>.jpg (+ index.json
           with each film's runtime, where its credits start and where its sheet starts).
           Look at them and note roughly where each scene is.
  sheet FILM FROM SECONDS
           one extra sheet of a film, from FROM on (say, a mid-credits scene that starts
           before the usual sheet): OUT/<tmdb>-<from>.jpg
  snap FILM T [T …]
           each rough time T (seconds) moved to the nearest cut or fade to black within
           ±8 s: a scene's exact start or end.
  snap-all ROUGH.json OUT.json
           every scene start and end in a table snapped like that. ROUGH is
           {"<tmdb>": {"runtime": s, "credits": s, "scenes": [{"start": s, "end": s, "kind":
           "mid"|"post"[, "spoiler": true]}]}} (start from index.json); OUT.json is in the same
           shape, ready to paste into a universe's "scenes".

FILM is a TMDb id or a Jellyfin item id. The films are those in the story lists of the
configured universes, or only the ones you name with --item (a Jellyfin item id; repeat it).

Where the credits start: the first "Outro" media segment (from a segment plugin such as
Intro Skipper), else a chapter named "...credits...", else 12 minutes before the end.

ffmpeg runs in Jellyfin's own image (it has jellyfin-ffmpeg), with your media read-only.

Environment:
  JELLYFIN_URL, JELLYFIN_API_KEY   as for universes.py
  MEDIA_DIR     the host folder that Jellyfin sees as MEDIA_MOUNT (required for the container)
  MEDIA_MOUNT   that folder's path inside Jellyfin (default /media): file paths start with it
  OUT           where the sheets go (default ./credits-sheets)
  CONTAINER     podman (default), docker, or none (run ffmpeg from PATH; paths are rewritten
                from MEDIA_MOUNT to MEDIA_DIR when MEDIA_DIR is set)
  FFMPEG_IMAGE  default docker.io/jellyfin/jellyfin:latest
"""
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("universes", os.path.join(HERE, "universes.py"))
U = importlib.util.module_from_spec(spec)
spec.loader.exec_module(U)

OUT = os.path.abspath(os.environ.get("OUT", "credits-sheets"))
MEDIA_DIR = os.environ.get("MEDIA_DIR")
MEDIA_MOUNT = os.environ.get("MEDIA_MOUNT", "/media").rstrip("/")
CONTAINER = os.environ.get("CONTAINER", "podman")
IMAGE = os.environ.get("FFMPEG_IMAGE", "docker.io/jellyfin/jellyfin:latest")
STEP = 4
COLS, ROWS = 10, 36  # 360 frames: 24 minutes
BEFORE = 300  # styled end titles and a mid-credits scene often come before the crawl a segment plugin marks


def out(name):
    """A file in OUT, as ffmpeg sees it."""
    return f"/out/{name}" if CONTAINER != "none" else os.path.join(OUT, name)


def media(path):
    """A film's path (as Jellyfin has it), as ffmpeg sees it."""
    if CONTAINER == "none" and MEDIA_DIR and path.startswith(MEDIA_MOUNT + "/"):
        return MEDIA_DIR.rstrip("/") + path[len(MEDIA_MOUNT):]
    return path


def ff(tool, *args):
    """Jellyfin's ffmpeg/ffprobe in a container of its own, the media read-only."""
    if CONTAINER == "none":
        cmd = [tool]
    else:
        if CONTAINER not in ("podman", "docker"):
            sys.exit(f"CONTAINER must be podman, docker or none, not {CONTAINER!r}")
        if not MEDIA_DIR:
            sys.exit(f"set MEDIA_DIR to the host folder Jellyfin sees as {MEDIA_MOUNT}")
        cmd = [CONTAINER, "run", "--rm", "--security-opt", "label=disable", "-v", f"{MEDIA_DIR}:{MEDIA_MOUNT}:ro", "-v", f"{OUT}:/out",
               "--entrypoint", f"/usr/lib/jellyfin-ffmpeg/{tool}", IMAGE]
    return subprocess.run([*cmd, "-v", "error", *args], capture_output=True, text=True)


def _film(i):
    """(tmdb, title, id, path, runtime s, credits start s) of a library film."""
    runtime = (i.get("RunTimeTicks") or 0) / 1e7
    outro = [s["StartTicks"] / 1e7 for s in (U.req("GET", f"/MediaSegments/{i['Id']}") or {}).get("Items", []) if s["Type"] == "Outro"]
    chapter = [c["StartPositionTicks"] / 1e7 for c in i.get("Chapters") or [] if re.search(r"credits", c.get("Name") or "", re.I)]
    credits = min(outro or chapter or [max(0, runtime - 720)])
    tmdb = (i.get("ProviderIds") or {}).get("Tmdb") or i["Id"]
    return tmdb, i["Name"], i["Id"], i["Path"], runtime, credits


_lib = None


def library():
    global _lib
    if _lib is None:
        uid = U.admin_user()
        _lib = U.req("GET", "/Items", userId=uid, recursive="true", includeItemTypes="Movie",
                     fields="ProviderIds,Path,Chapters")["Items"]
    return _lib


def films(a):
    """The films to make sheets of: --item ones, else every film on the configured universes' paths."""
    lib = library()
    if a.item:
        chosen = [i for i in lib if i["Id"] in a.item]
        missing = set(a.item) - {i["Id"] for i in chosen}
        if missing:
            print("not films in the library:", ", ".join(sorted(missing)))
    else:
        try:
            universes = U.load_config(a.config)
        except U.ConfigError as e:
            sys.exit(f"config: {e} (or name films with --item)")
        wanted = {str(tmdb) for u in universes for kind, tmdb, _, _ in u.story if kind == "movie"}
        chosen = [i for i in lib if (i.get("ProviderIds") or {}).get("Tmdb") in wanted]
    return [_film(i) for i in chosen if i.get("Path")]


def film(ref):
    """One film by TMDb id or Jellyfin item id."""
    i = next((i for i in library() if i["Id"] == ref or (i.get("ProviderIds") or {}).get("Tmdb") == str(ref)), None)
    if not i or not i.get("Path"):
        sys.exit(f"no film {ref} in the library")
    return _film(i)


def sheets(a):
    os.makedirs(OUT, exist_ok=True)
    index = {}
    for tmdb, title, _, path, runtime, credits in films(a):
        start = max(0, credits - BEFORE)
        frames = min(COLS * ROWS, int((runtime - start) / STEP) + 1)
        # Keyframes only: much faster, and close enough (snap finds the exact cuts).
        r = ff("ffmpeg", "-y", "-skip_frame", "nokey", "-ss", f"{start:.1f}", "-i", media(path), "-vf", f"fps=1/{STEP},scale=192:-2,tile={COLS}x{ROWS}",
               "-frames:v", "1", "-q:v", "4", out(f"{tmdb}.jpg"))
        index[tmdb] = {"title": title, "runtime": round(runtime, 1), "credits": round(credits, 1), "start": round(start, 1),
                       "step": STEP, "frames": frames, "ok": r.returncode == 0}
        print(f"{title}: credits at {credits:.0f}s of {runtime:.0f}s, sheet from {start:.0f}s{'' if r.returncode == 0 else ' FAILED ' + r.stderr[-200:]}", flush=True)
    with open(f"{OUT}/index.json", "w") as f:
        json.dump(index, f, indent=1)


def sheet(ref, start, seconds):
    tmdb, _, _, path, _, _ = film(ref)
    os.makedirs(OUT, exist_ok=True)
    r = ff("ffmpeg", "-y", "-skip_frame", "nokey", "-ss", f"{start:.1f}", "-i", media(path), "-t", f"{seconds:.0f}",
           "-vf", f"fps=1/{STEP},scale=192:-2,tile={COLS}x{ROWS}", "-frames:v", "1", "-q:v", "4", out(f"{tmdb}-{start:.0f}.jpg"))
    print(f"{OUT}/{tmdb}-{start:.0f}.jpg" if r.returncode == 0 else r.stderr[-300:])


def nearest(path, t):
    """The cut or fade to black nearest to T (seconds) within ±8 s, else None."""
    a = max(0, t - 8)
    # Both filters report at info level (ff() runs at error level otherwise).
    r = ff("ffmpeg", "-v", "info", "-ss", f"{a:.1f}", "-t", "16", "-i", media(path), "-vf", "scdet=t=8,blackdetect=d=0.2:pix_th=0.1", "-an", "-f", "null", "-")
    marks = [a + float(x) for x in re.findall(r"lavfi\.scd\.time: ([\d.]+)", r.stderr)]
    marks += [a + float(x) for x in re.findall(r"black_(?:start|end):([\d.]+)", r.stderr)]
    return min(marks, key=lambda m: abs(m - t), default=None)


def snap(ref, times):
    path = film(ref)[3]
    for t in times:
        best = nearest(path, t)
        print(f"{t}: {best:.1f}" if best is not None else f"{t}: no cut or fade nearby", flush=True)


def snap_all(rough, dest):
    """Every scene's start and end in ROUGH snapped to its cut, into DEST; an end at the end
    of the film stays."""
    table = json.load(open(rough))
    for ref, v in table.items():
        if ref.startswith("_"):
            continue
        path = film(ref)[3]
        for sc in v["scenes"]:
            for k in ("start", "end"):
                if k == "end" and sc["end"] >= v["runtime"] - 2:
                    continue
                m = nearest(path, sc[k])
                if m is not None:
                    sc[k] = round(m, 1)
        print(f"{v.get('title', ref)}: {v['scenes']}", flush=True)
    with open(dest, "w") as f:
        json.dump({k: {x: v[x] for x in ("runtime", "credits", "scenes")} for k, v in table.items() if not k.startswith("_")}, f, indent=1)
    print("paste", dest, "into the universe's \"scenes\"")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0], epilog="See the module docstring (head of this file) for details.")
    p.add_argument("--config", default=U.DEFAULT_CONFIG, help="the universes config, for the list of films")
    p.add_argument("--item", action="append", default=[], help="only this Jellyfin item id (repeatable)")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("sheets")
    s = sub.add_parser("sheet")
    s.add_argument("film")
    s.add_argument("start", type=float)
    s.add_argument("seconds", type=float)
    s = sub.add_parser("snap")
    s.add_argument("film")
    s.add_argument("times", type=float, nargs="+")
    s = sub.add_parser("snap-all")
    s.add_argument("rough")
    s.add_argument("out")
    a = p.parse_args()
    if a.cmd == "sheets":
        sheets(a)
    elif a.cmd == "sheet":
        sheet(a.film, a.start, a.seconds)
    elif a.cmd == "snap":
        snap(a.film, a.times)
    else:
        snap_all(a.rough, a.out)


if __name__ == "__main__":
    main()
