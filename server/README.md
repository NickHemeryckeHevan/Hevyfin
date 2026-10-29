# Server helpers

Optional scripts to run on the machine next to your Jellyfin server. Hevyfin works without
them. They add things the app can show when they are there:

| Script | What it does | How often |
| --- | --- | --- |
| `universes.py` | Builds "universe" collections in story order, with chapters, a timeline and what's still missing. | Daily |
| `credits-scenes.py` | Helps you find mid- and post-credits scenes, so the player skips the credits but not the scenes. | By hand |
| `cinema-trailers.py` | Keeps trailers of the movies now in cinemas, for cinema mode and the TV channels. | Daily |
| `library-trailers.py` | Keeps a trailer of every film and series in your library, for the Trailer button. | Daily |
| `art/make_grid_poster.py` | Makes a collection poster from 9 posters in a grid. | By hand |
| `art/make_cut_poster.py` | Makes a poster for a cut of a show's episodes. | By hand |

`web/` holds the files to serve the browser version yourself (see `docs/self-hosting-web.md`).

How collections work in the app, and how to make your own by hand or with `universes.py`:
[docs/custom-collections.md](../docs/custom-collections.md).

## What you need

- Python 3.10 or newer. No packages, except Pillow for the poster scripts (`pip install pillow`).
- For the trailer scripts: podman or docker (they run yt-dlp in a container), or `yt-dlp` on
  your PATH with `CONTAINER=none`.
- For `credits-scenes.py`: podman or docker (it uses the ffmpeg in Jellyfin's own image), or
  `ffmpeg` on your PATH with `CONTAINER=none`.
- For the trailer scripts: [Seerr](https://github.com/seerr-team/seerr) (or Jellyseerr), for TMDB
  data. `library-trailers.py` can do without it, with fewer trailers.

## Install

Copy this folder somewhere, for example `/opt/hevyfin-server`. Keep `universes.py` and
`credits-scenes.py` side by side: the second one imports the first.

Put your settings in one file that only root can read, for example `/etc/hevyfin/hevyfin.env`:

```sh
JELLYFIN_URL=http://127.0.0.1:8096
JELLYFIN_API_KEY=your-jellyfin-api-key   # Dashboard > API keys
SEERR_URL=http://127.0.0.1:5055
SEERR_API_KEY=your-seerr-api-key         # Seerr: Settings > General
CINEMA_DIR=/data/media/Cinema            # the Cinema folder on this machine, see below
CONTAINER=podman                         # or docker, or none
```

```sh
sudo install -d -m 0755 /etc/hevyfin
sudo install -m 0600 hevyfin.env /etc/hevyfin/hevyfin.env
```

## Environment variables

**All scripts that talk to Jellyfin**

| Variable | Default | Meaning |
| --- | --- | --- |
| `JELLYFIN_URL` | `http://127.0.0.1:8096` | Your Jellyfin server. |
| `JELLYFIN_API_KEY` | (required) | An API key from Dashboard > API keys. |

**universes.py**

| Variable | Default | Meaning |
| --- | --- | --- |
| `UNIVERSES_CONFIG` | `/etc/hevyfin/universes.json` | The config, if you don't pass `--config`. |
| `CACHE_DIR` | `/var/lib/hevyfin-universes` | Last Wikidata answers (used when it's down) and `last-run.txt`. |
| `ART_DIR` | `art/` next to the config | Posters for cuts of episodes. |
| `SONARR_URL`, `SONARR_API_KEY` | (unset) | Optional. Shows Sonarr is still fetching are marked "On its way". |
| `RADARR_URL`, `RADARR_API_KEY` | (unset) | Optional. The same for films in Radarr. |

**credits-scenes.py**

| Variable | Default | Meaning |
| --- | --- | --- |
| `MEDIA_DIR` | (required with a container) | The host folder that Jellyfin sees as `MEDIA_MOUNT`. |
| `MEDIA_MOUNT` | `/media` | That folder's path inside Jellyfin. File paths in Jellyfin start with it. |
| `OUT` | `./credits-sheets` | Where the contact sheets go. |
| `CONTAINER` | `podman` | `podman`, `docker` or `none`. |
| `FFMPEG_IMAGE` | `docker.io/jellyfin/jellyfin:latest` | The image whose ffmpeg is used. |

**cinema-trailers.py and library-trailers.py**

| Variable | Default | Meaning |
| --- | --- | --- |
| `CINEMA_DIR` | `/media/Cinema` | The Cinema folder on this machine. |
| `SEERR_URL` | `http://127.0.0.1:5055` | Your Seerr. |
| `SEERR_API_KEY` | (required for cinema-trailers) | Seerr's API key. |
| `CINEMA_TOTAL` | `40` | cinema-trailers: how many movies at most. |
| `CINEMA_WEEKS` | `8` | cinema-trailers: released this many weeks ago or less counts as "in cinemas". |
| `CINEMA_LANGUAGES` | `en` | cinema-trailers: original languages to keep, e.g. `en,fr`. Empty: any. |
| `STATE_DIR` | `/var/lib/hevyfin-trailers` | library-trailers: remembers failed downloads (retried after a week). |
| `CONTAINER` | `podman` | `podman`, `docker` or `none` (yt-dlp from your PATH). |
| `YTDLP_IMAGE` | `docker.io/jauderho/yt-dlp:latest` | The yt-dlp image. |

**art/\*.py**

| Variable | Default | Meaning |
| --- | --- | --- |
| `FONT` | Lato, where distributions install it | A font path with `{}` for the weight (`Heavy`, `Black`), or one font file. Same as `--font`. |

## The Cinema library

The trailer scripts write into one folder, called `Cinema`, with two folders inside:

```
Cinema/
  Trailers/   trailers of movies now in cinemas (cinema-trailers.py)
              cinema mode and the TV channels play these before a movie
  Library/    movie-<tmdb>.mp4 and tv-<tmdb>.mp4 (library-trailers.py)
              the Trailer button on a title's page plays these
```

The app finds the videos by their path, so keep the names `Cinema`, `Trailers` and `Library`.
You can also put trailers of your own in `Cinema/Trailers/`. `cinema-trailers.py` deletes
any file there that isn't on its list, so if you add your own, don't run that script.

Then, in Jellyfin:

1. Add the `Cinema` folder as a library of type **Home videos and photos**.
2. Hide it from people's views. Signed in as each user, open **Settings > Home** and, for
   the Cinema library, untick **Display in My Media** (this is the user's `MyMediaExcludes`)
   and **Display in other home screen sections**.
3. Keep each user's access to the library. The app reads the videos as that user. Without
   access, they find no trailers.

## Running them on a timer

Example systemd units. Change the paths to where you put the scripts and files. Put each
file in `/etc/systemd/system/`, then run `sudo systemctl daemon-reload` and
`sudo systemctl enable --now <name>.timer`.

`hevyfin-universes.service`:

```ini
[Unit]
Description=Hevyfin: keep universe collections in story order
After=network-online.target jellyfin.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/hevyfin/hevyfin.env
ExecStart=/usr/bin/python3 /opt/hevyfin-server/universes.py --config /etc/hevyfin/universes.json
StateDirectory=hevyfin-universes
```

`hevyfin-universes.timer`:

```ini
[Unit]
Description=Hevyfin: universe collections, daily

[Timer]
OnCalendar=*-*-* 05:30
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
```

`hevyfin-cinema-trailers.service`:

```ini
[Unit]
Description=Hevyfin: trailers of the movies in cinemas
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/hevyfin/hevyfin.env
ExecStart=/usr/bin/python3 /opt/hevyfin-server/cinema-trailers.py
```

`hevyfin-library-trailers.service`:

```ini
[Unit]
Description=Hevyfin: a trailer for every title in the library
After=network-online.target jellyfin.service
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/hevyfin/hevyfin.env
ExecStart=/usr/bin/python3 /opt/hevyfin-server/library-trailers.py
StateDirectory=hevyfin-trailers
```

Give each of the two trailer services a timer like the one above, named the same as its
service (`hevyfin-cinema-trailers.timer`, `hevyfin-library-trailers.timer`), at a time of
your choice. The first run of `library-trailers.py` can take long on a big library; pass a
number to cap the downloads per run, e.g. `library-trailers.py 50`.

See what a run did with `journalctl -u hevyfin-universes` (and the same for the others).
`universes.py` also keeps its last run's output in `$CACHE_DIR/last-run.txt`.

## About the trailers

The trailer scripts only download official trailers that TMDB links to, for private viewing
on your own server. You are responsible for following YouTube's and TMDB's terms of use and
the law where you live. If in doubt, don't run them: the app works without them.
