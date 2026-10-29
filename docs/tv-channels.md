# Cinema, TV channels and Free TV

Hevyfin's **Live** tab (on Android TV / Google TV and in the Linux and Android apps) has three
kinds of "on the clock" viewing:

| What | Where it comes from | What you need on the server |
|---|---|---|
| **Cinema** | Your movies, three screenings a day | Movies in Jellyfin. Trailers are optional. |
| **House channels** 1–4 | Your movies and episodes, on a 24-hour schedule | Movies and series in Jellyfin. A `lol-tv` tag is optional. |
| **Free TV** (channel 5 and up) | Live streams | Jellyfin's own Live TV (an M3U tuner + an XMLTV guide). |

Everything runs on the clock: join late and you land wherever the show is now. Schedules are
built once a day on each device, from the same seed, so every screen in the house shows the
same thing at the same time. Hevyfin plays **no ads**.

## Cinema

Three screenings a day, at random times in three windows (13:00–16:30, 17:30–20:00,
20:30–22:30). Better-reviewed movies come up more often, and only acclaimed ones (critics
80+ or community 7.5+) may play twice in a day. On some weekdays the evening screening has a
theme: horror on Friday, family on Saturday, sci-fi on Sunday, comedy on Wednesday and action
on Thursday (`cinemaThemes` in `lib/state/live.dart`).

Each screening goes:

1. **"Hevyfin presents"** (the ident),
2. the evening's **theme** card, if the film fits one,
3. **up to five trailers** of films now in cinemas, if you have any (see below),
4. **"Phones on silent, screens down."**,
5. the **feature intro**: the poster, the cast and a countdown,
6. the film, with a 10-minute **intermission** halfway.

**With no trailers**, it goes straight from step 1 (and 2) to the phone card and the countdown.

From any movie's page, **Cinema mode** gives you a private screening that starts right away.
**Marathons** (Cinema tab → plan a marathon) chain several films with breaks you choose. They
are saved in Jellyfin's own DisplayPreferences, so they work on any Jellyfin server and
follow you to every device.

### Trailers (optional)

The pre-show trailers come from a hidden Jellyfin library:

```
<media>/Cinema/
├── Trailers/      trailers of films now in cinemas: played in the pre-show and channel breaks
└── Library/       one trailer per title in your library, for the Trailer button
                   (movie-<tmdb id>.mp4, tv-<tmdb id>.mp4)
```

1. Make the folders and add `<media>/Cinema` to Jellyfin as a **Home videos and photos** library.
2. Hide it from everyone's home screen, but **keep their access** to it (the app reads the
   trailers as the signed-in user): each user → Settings → Home → untick the Cinema library
   under "Display in My Media" and "Display in other home screen sections". The folder names
   `Cinema`, `Trailers` and `Library` must be spelled exactly so: Hevyfin finds them by path.
3. Fill it, by hand or with `server/cinema-trailers.py` (Trailers/) and
   `server/library-trailers.py` (Library/). See `server/README.md`.

Only paths that contain `/Cinema/Trailers/` count as pre-show trailers, so a normal movie
library is never mixed in. Without `Library/`, the Trailer button plays the title's YouTube
trailer from TMDb instead. Only use trailers you're allowed to download and keep (see
[DISCLAIMER.md](../DISCLAIMER.md)).

## House channels

| # | Name | Plays |
|---|---|---|
| 1 | Movie Night | mostly movies, with series between them |
| 2 | Hevyfin Mix | mostly series, now and then a movie |
| 3 | Cartoons / After Hours | animated, age 12 and under, 08:00–20:00; after 20:00 it becomes **After Hours**: shows rated 14+ |
| 4 | LOL TV | only series tagged `lol-tv`, often two or three episodes back to back |

A channel day runs 06:00 to 06:00, like a broadcaster's. Random episodes of every series are
mixed together. Movies are rare: at most one an evening, between 20:00 and midnight, and only
badly rated ones (the "late movie"). A title never plays on two channels at once.

Between programmes there's a short **break**: the channel's ident, now and then a trailer
(when you have any), and an "Up next" card, so the next programme starts on a 5-minute mark.

### Choosing what LOL TV plays

Tag series with `lol-tv` in Jellyfin (the series → ⋯ → Edit metadata → Tags). Those series
only play on LOL TV. Without any, LOL TV has nothing to play and only shows its breaks.

### Adding, renaming or changing a channel

The channels are defined in code, so you change them and build the app yourself
([building.md](building.md)):

- **The list**: `channels` in `lib/state/live.dart`:
  ```dart
  const channels = [
    Channel(1, 'Movie Night', .6),        // number, name, share of movies (the rest is episodes)
    Channel(2, 'Hevyfin Mix', .3),
    Channel(3, 'Cartoons', .4),           // channel 3 is split by day and night (Channel.split)
    Channel(4, 'LOL TV', 0, sitcoms: true),
  ];
  ```
  Add `Channel(5, 'Westerns', .5)` and it gets its own schedule. Free TV channels keep the
  numbers Jellyfin gives them, so start those after your house channels.
- **What a channel may play**: `channelDays()` in the same file. `fits()` holds the
  day/night rule of the split channel, and `sitcom()` in `lib/state/live_store.dart` picks the
  `lol-tv` series. Filter on genre, rating (`Title.age`), `animated`, or your own tag, the same way.
- **Its look**: `ChannelIdent` in `lib/ui/widgets/live_bumpers.dart` draws each channel's logo
  (`_logo()`, one `case` per number) and the 5-second ident in its breaks. Bumpers are plain
  Flutter widgets (text, shapes, gradients, opacity), so they stay smooth on a Chromecast.
- **The sound** at the countdown and idents is `assets/live/sting.ogg`. Swap in your own
  (keep it short, about 3 s, and make sure you may use it).
- `flutter test test/live_test.dart` checks the schedules: no overlaps, no ads, the pre-show order.

Please don't name channels after real broadcasters or copy their logos.

## Free TV (channel 5 and up)

Free TV is Jellyfin's own **Live TV**. Whatever channels your Jellyfin server has show up after
the house channels, with the guide.

1. **Get an M3U playlist** of streams you're allowed to watch: your own TV tuner or IPTV
   subscription, or broadcasters' official free streams. An entry looks like:
   ```
   #EXTM3U
   #EXTINF:-1 tvg-id="example.news" tvg-chno="5" tvg-logo="https://example.org/logo.png",Example News
   https://example.org/live/news/master.m3u8
   ```
   `tvg-chno` is the channel number Hevyfin shows. Start at 5, after the house channels.
2. In Jellyfin: Dashboard → Live TV → **Tuner devices** → add **M3U Tuner** with the
   playlist's file or URL.
3. Add a **TV guide data provider** → **XMLTV** with a guide whose channel ids match the
   playlist's `tvg-id`.
4. Refresh the guide (Dashboard → Scheduled tasks → Refresh Guide). The channels appear in
   Hevyfin's Live tab within ten minutes, or at once after a restart of the app.

Hevyfin plays each channel's own stream address straight from the source (no work for the
server) and picks the best quality up to 1080p. That works for **HTTP(S) HLS (`.m3u8`) and
plain HTTP streams**. Tuners whose streams only Jellyfin itself can open (for example some
HDHomeRun setups) may not play.

Only add streams you're allowed to watch where you live. Hevyfin doesn't come with any.
