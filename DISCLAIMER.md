# Disclaimer

Please read this before you use, build, host or share Hevyfin. It's written in plain words;
the [LICENSE](LICENSE) (GNU GPL v3) is the binding text, and nothing here limits the rights
it gives you.

## Not affiliated

Hevyfin is an independent, unofficial, non-commercial project. It is **not affiliated with,
endorsed by or sponsored by** Jellyfin, Netflix, Seerr / Jellyseerr / Overseerr, Sonarr,
Radarr, Prowlarr, qBittorrent, TMDB, Google, YouTube or any broadcaster, studio or
streaming service. Their names are used only to say what Hevyfin works with. All trademarks,
logos and brand names belong to their owners.

"Streaming-service style" describes a common look (dark pages, rows of posters, a big
artwork banner). Hevyfin doesn't use anyone else's logos, fonts, sounds or artwork.

## No content included

Hevyfin is a **player and remote for your own server**. It ships with **no movies, shows,
music, streams, channel lists, indexers, subtitles or artwork**, and it doesn't tell you
where to get any. Posters, descriptions and trailers you see come from your own server and
the metadata services you have set up.

**You are responsible** for what you add to your server and for having the right to play,
stream, share, record or download it where you live. Only add TV streams you're allowed to
watch (your own tuner or subscription, or a broadcaster's official free stream), and only
keep trailers you're allowed to keep.

## Optional download tools (admin panel)

Hevyfin Admin can show the status of download software **you install and configure yourself**
(qBittorrent, Prowlarr, Sonarr, Radarr) and can list search results (release-watch). These
parts are **off unless you set them up**, and release-watch never downloads anything by itself.
They are meant for content you have the right to download: your own files, public-domain or
freely licensed works, and releases you are licensed to get. **Don't use them to infringe
copyright.** The authors don't host, link to, index or distribute any content and have no
control over what you connect the software to.

## Third-party services

- **TMDB**: This product uses the TMDB API but is not endorsed or certified by TMDB.
  Metadata and images from TMDB are subject to [TMDB's terms of use](https://www.themoviedb.org/api-terms-of-use).
- **YouTube** trailers open or play under YouTube's own terms. The optional
  `server/*-trailers.py` scripts use yt-dlp: check YouTube's terms and your local law before you
  run them, and only keep what you may keep.
- **Wikidata** (used by the optional `server/universes.py`) data is CC0.

## Privacy

Hevyfin has **no analytics, tracking or telemetry**, and no server of its own. It talks to
the servers you give it: your Jellyfin, your Seerr, and (only if you set one) your own
recommendation service ([docs/niql.md](docs/niql.md)), which gets your Jellyfin sign-in with each
question. Besides those, your device loads:

- posters of titles that aren't in your library yet straight from TMDB's image server
  (`image.tmdb.org`), on the Seerr pages;
- the Inter Tight font from Google Fonts in the apps (the google_fonts package; the browser
  version bundles its own copy);
- YouTube, when you play a trailer that your server doesn't have.

Those services see your IP address, like any website you visit. Sign-ins are stored on your device. If you host the web version or the admin panel,
**you** are the operator: keep them on your LAN or VPN, and follow your local privacy rules
for the people who use them.

## No warranty

Hevyfin is free software, provided **"as is", without warranty of any kind**, express or
implied, including the implied warranties of merchantability and fitness for a particular
purpose. In no event will the authors or contributors be liable for any damages arising from
its use, including the loss of data, accounts, media or files: the admin panel can delete
films, shows and their files, and change or switch off accounts, so use it with care. See
sections 15 and 16 of the [LICENSE](LICENSE).

## Questions or concerns

If you believe something in this repository infringes your rights, open an issue on GitHub
and it will be looked at and removed if needed.
