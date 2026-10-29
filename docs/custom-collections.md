# Custom collections and universes

Hevyfin can show a collection as a "universe": a set of films and series watched in story
order, split into chapters, with a timeline, a page of its own and help with credits scenes.
Everything lives on your Jellyfin server, as tags and provider ids on the items. A new
collection needs no new app version.

This page explains what the app reads, then three ways to set it up:

1. [By hand](#doing-it-by-hand), in Jellyfin's web UI and with its API.
2. [With `server/universes.py`](#with-universespy), a daily job that does it from a config file.
3. [Credits scenes](#credits-scenes) and [posters](#posters), with the other helper scripts.

The examples use a made-up universe, "Example Saga". Its TMDb ids (1, 2, 3) are placeholders.
Put in the real ids from [themoviedb.org](https://www.themoviedb.org).

## What the app reads

### Which collections show up

The Collections view lists two kinds of collections (box sets):

- Box sets whose name ends in "Collection", like the ones TMDb makes ("… Collection").
- Box sets tagged `franchise`. These count as universes and are listed first.

Other box sets (genre groupings made by a plugin, say) are left out.

### Story order: `story:` tags

Put a tag on each film or series in the collection:

```
story:<collection name>:<place>
```

For example `story:Example Saga:01`, `story:Example Saga:02`. The name must match the
collection's name exactly. The place is a number; leading zeros are fine.

When titles carry these tags, the collection's page gets a **Release order / Story order**
switch. Each person chooses for themselves. Titles without a tag go after the tagged ones.
"Play" and "next up" follow the chosen order.

### Chapters: `group:` tags

```
group:<collection name>:<chapter>
```

For example `group:Example Saga:Part One`. A custom page with a `groups` section shows the
chapters as rows. Titles without a chapter go under "More". With no chapters at all, the
section isn't shown.

### What's missing: `missing:`, `upcoming:` and `coming:` tags

These tags go on the collection itself:

| Tag | Meaning |
| --- | --- |
| `missing:<kind>:<tmdb>` | Released, but not in your library. `kind` is `movie` or `tv`. |
| `upcoming:<kind>:<tmdb>:<date>` | Not out yet. `date` is `YYYY-MM-DD`, or empty when not dated yet. |
| `coming:<kind>:<tmdb>` | Missing, but already being downloaded. Shown as "On its way". |

For example `missing:movie:3` and `upcoming:movie:4:2030-05-01`. They show in the `missing`
and `upcoming` sections of a custom page, with posters from Seerr. They need Seerr to be
set up in the app. A title that is requested or downloading in Seerr also counts as on its way.

### The page design: provider id `HevyfinPage`

A collection can carry its own page design. It is a JSON object, stored as a string in the
collection's provider ids under the key `HevyfinPage` (spelled exactly like that). Without
it, the collection gets the standard page.

```json
{
  "accent": "#2a9d8f",
  "eyebrow": "A story in four parts",
  "tagline": "Two twins, one map, and the long way home.",
  "sections": [
    {"type": "intro", "text": "The Example Saga follows the twins from the day they find the map.\n\nWatch it in story order, or as it came out."},
    {"type": "progress"},
    {"type": "timeline", "title": "The path"},
    {"type": "groups", "title": "Chapters"},
    {"type": "quote", "text": "Every map is a promise.", "by": "The old cartographer"},
    {"type": "heroes", "title": "The faces of the saga"},
    {"type": "facts", "title": "Did you know", "items": ["It was filmed on three islands.", "The map is a real antique."]},
    {"type": "missing"},
    {"type": "upcoming", "title": "Coming soon"}
  ]
}
```

Top-level fields:

| Field | Meaning |
| --- | --- |
| `accent` | A colour, `#rrggbb` or `rrggbb`. Used for headings, the play button and the glow. |
| `eyebrow` | A small line above the name, shown in capitals. |
| `tagline` | A line under the name. Without it, the collection's own tagline is used. |
| `sections` | The page's sections, in order. Leave one out and it isn't shown. |

Section types. Every section can have a `title`, which replaces the default heading.

| `type` | What it shows | Other fields |
| --- | --- | --- |
| `intro` | Large text. | `text`; a blank line starts a new paragraph. |
| `text` | Normal text. | `text`, as above. |
| `quote` | A quote. | `text`, and `by` for who said it. |
| `progress` | A ring with how much you've watched. | |
| `timeline` | The path: every stop, in the chosen order. | |
| `groups` | The chapters, one row each. | |
| `heroes` | The actors who appear most, with their roles. | |
| `facts` | Numbered facts. | `items`: a list of strings. Without it, facts are worked out from the titles. |
| `missing` | What's not in your library yet. | `items`: optional, see below. |
| `upcoming` | What's not out yet, soonest first. | `items`: optional, see below. |

`missing` and `upcoming` read the collection's tags. You can give a list instead:
`"items": [{"kind": "movie", "tmdb": 3, "date": "2030-05-01"}]` (`kind` defaults to `movie`;
`date` is optional).

The page's hero (the titles' backdrops, the counters and the play button) is always there.

### The timeline: provider id `HevyfinStory`

Normally, each title in the collection is one stop on the path. The timeline can do more: a
series can be split into stops of one season, or of a hand-picked set of episodes (a "cut"),
each placed where it falls in the story.

It is a JSON array, stored as a string in the collection's provider ids under `HevyfinStory`:

```json
[
  {"kind": "movie", "ids": ["<film item id>"], "title": "Example Saga: The Beginning",
   "date": "2001-03-09", "group": "Part One"},
  {"kind": "season", "ids": ["<episode id>", "<episode id>", "<episode id>"], "series": "<series item id>",
   "season": 1, "title": "The First Winter", "code": "Season 1", "date": "2003-01-10",
   "group": "Part One", "mini": true,
   "previously": "In The Beginning, the twins found the map and lost their home."},
  {"kind": "cut", "ids": ["<episode id>", "<episode id>"], "series": "<series item id>",
   "season": 2, "title": "The Lost Map", "code": "S2 · E1–2", "date": "2004-01-02",
   "art": {"id": "<episode id>", "tag": "<its Box image tag>"}, "group": "Side Stories",
   "previously": "The First Winter ended with the map stolen from the twins' camp."},
  {"kind": "movie", "ids": ["<film item id>"], "title": "Example Saga: The Return", "date": "2006-07-14"}
]
```

All ids are Jellyfin item ids. Fields of a stop:

| Field | Meaning |
| --- | --- |
| `kind` | `movie` or `series` for a whole title; `season` or `cut` for part of a series. |
| `ids` | A whole title: its item id. A season or cut: its episodes' ids, in order. |
| `series` | Seasons and cuts only: the series' item id. |
| `season` | Seasons and cuts: the season number. |
| `title` | The stop's name. A season or cut can have a name of its own. |
| `code` | Seasons and cuts: the small label under the name, like `Season 1` or `S2 · E1–2`. |
| `date` | `YYYY-MM-DD`. Used for release order. |
| `group` | The stop's chapter. Without it, the title's `group:` tag is used. |
| `previously` | What to remember from the stops before. Shown on the title's page when opened from the path. Keep it free of spoilers for later stops. |
| `art` | A cut's own poster: an item id and the tag of its **Box** image. Without it, the show's or season's poster is used. |
| `mini` | `true`: the season or cut opens as a mini series of its own. |

Rules:

- The film or series of each stop must be in the collection. Stops whose title isn't are
  skipped.
- Titles in the collection but not in the list get a stop of their own, after the list.
- In release order, the stops are sorted by `date`. In story order, they keep the list's order.
- Without `HevyfinStory`, every title is one stop.

### Credits scenes: provider id `HevyfinScenes`

On a film, this holds where its credits start and its mid- and post-credits scenes. The
player then offers "Skip to mid-credits scene" (or post-credits) during the credits, and
waits for the last scene before it counts down to the next title. A scene marked as a
spoiler (it gives a later stop away) gets a "Skip spoiler" button instead.

It is a JSON object, stored as a string on the film under `HevyfinScenes`. Times are in
seconds:

```json
{"credits": 5710, "scenes": [
  {"start": 5788, "end": 5850.5, "kind": "mid"},
  {"start": 5960, "end": 6012.4, "kind": "post", "spoiler": true}
]}
```

`kind` is `mid` or `post`. `spoiler` is optional. The times only fit the file they were
measured on: if you replace the file, measure again.

## Doing it by hand

### In Jellyfin's web UI

1. Make the collection: on a film, open the menu (⋯) and choose **Add to collection**, then
   **New collection**. Name it "Example Saga". Add the other titles the same way.
2. Open the collection, choose **Edit metadata** and add the tag `franchise`.
3. On each title, choose **Edit metadata** and add its tags:
   `story:Example Saga:01` and `group:Example Saga:Part One`, and so on.
4. Optional: add `missing:movie:3` (and the like) to the collection's tags.

That gives you a universe with a story order and chapters. Jellyfin's UI can't set custom
provider ids, so for `HevyfinPage`, `HevyfinStory` and `HevyfinScenes` use the API.

### With the API

Jellyfin updates an item when you POST the whole item back to `/Items/{id}`. Read it, change
it, send it back. Leave out the read-only parts (`Trickplay`, `MediaSources`, `MediaStreams`,
`Chapters`, `UserData`); some of them make the update fail.

This needs `curl` and `jq`, and an API key (Dashboard > API keys).

```sh
JF=http://127.0.0.1:8096
AUTH="Authorization: MediaBrowser Token=\"your-api-key\""

# An administrator's user id (items are read as a user).
USER=$(curl -s -H "$AUTH" "$JF/Users" | jq -r '[.[] | select(.Policy.IsAdministrator)][0].Id')

# The collection's id. (It's also in the web UI's address bar: ...details?id=<id>.)
BOX=$(curl -s -H "$AUTH" "$JF/Items?userId=$USER&recursive=true&includeItemTypes=BoxSet&searchTerm=Example%20Saga" \
  | jq -r '.Items[] | select(.Name == "Example Saga") | .Id')

# Tag it as a universe and give it a page design (page.json holds the JSON from above).
curl -s -H "$AUTH" "$JF/Items/$BOX?userId=$USER" \
  | jq --rawfile page page.json '
      del(.Trickplay, .MediaSources, .MediaStreams, .Chapters, .UserData)
      | .Tags = ((.Tags // []) + ["franchise"] | unique)
      | .ProviderIds.HevyfinPage = ($page | fromjson | tojson)
      | .LockData = true' \
  | curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" -d @- "$JF/Items/$BOX"
```

`($page | fromjson | tojson)` checks the JSON and packs it into one line. The value must be
a string, not an object. `LockData` keeps Jellyfin's metadata refresh from changing the item.

The same pattern sets a title's tags:

```sh
ITEM=<the film's item id>
curl -s -H "$AUTH" "$JF/Items/$ITEM?userId=$USER" \
  | jq 'del(.Trickplay, .MediaSources, .MediaStreams, .Chapters, .UserData)
        | .Tags = ((.Tags // []) + ["story:Example Saga:01", "group:Example Saga:Part One"] | unique)' \
  | curl -s -X POST -H "$AUTH" -H "Content-Type: application/json" -d @- "$JF/Items/$ITEM"
```

`HevyfinStory` (on the collection) and `HevyfinScenes` (on a film) work like `HevyfinPage`:
put the JSON in a file and set `.ProviderIds.HevyfinStory` or `.ProviderIds.HevyfinScenes`.

A cut's poster is a **Box** image on its first episode (no app shows a Box image for an
episode, so it's free to use). Upload it, then read its tag for the stop's `art`:

```sh
EP=<the cut's first episode id>
base64 -w0 example-saga-the-lost-map.jpg \
  | curl -s -X POST -H "$AUTH" -H "Content-Type: image/jpeg" --data-binary @- "$JF/Items/$EP/Images/Box"
curl -s -H "$AUTH" "$JF/Items/$EP?userId=$USER" | jq -r '.ImageTags.Box'
```

## With universes.py

`server/universes.py` does all of the above for you, every day, from a config file. It:

- finds the titles of each universe in your library (by TMDb id, else by title) and puts
  them in the collection, making it if needed;
- tags each with its `story:` place and `group:` chapter;
- writes the `HevyfinStory` timeline, with seasons, cuts, recaps and posters;
- writes each film's `HevyfinScenes` from the config;
- tags the collection `franchise`, plus `missing:`, `upcoming:` and `coming:`;
- optionally asks Wikidata for the universe's titles, so new and announced ones turn up by
  themselves (they go at the end of the story, by release date).

It never touches `HevyfinPage`: set that by hand, as above.

Install it and set it on a timer as described in [server/README.md](../server/README.md).
Then write a config. Start from
[server/examples/universes.example.json](../server/examples/universes.example.json):

```sh
python3 server/universes.py --config universes.json --check   # read the config only
python3 server/universes.py --config universes.json           # run it
```

### The config file

A JSON file with a list of universes: `{"universes": [ … ]}`. Keys that start with `_` are
comments and are ignored.

```json
{
  "universes": [
    {
      "name": "Example Saga",
      "wikidata": [],
      "groups": {"Part One": ["movie:1", "tv:2"], "Part Two": ["movie:3"]},
      "latest": "Part Two",
      "story": [
        {"kind": "movie", "tmdb": 1, "title": "Example Saga: The Beginning"},
        {"kind": "tv", "tmdb": 2, "title": "Example Saga: The Series",
         "season": 1, "stop_title": "The First Winter",
         "previously": "In The Beginning, the twins found the map and lost their home."},
        {"kind": "tv", "tmdb": 2, "title": "Example Saga: The Series",
         "episodes": [[2, 1], [2, 2]], "stop_title": "The Lost Map",
         "art": "example-saga-the-lost-map.jpg", "group": "Side Stories"},
        {"kind": "movie", "tmdb": 3, "title": "Example Saga: The Return"}
      ],
      "mini": [2],
      "previously": {"Example Saga: The Return": "The twins got the map back. Now they head home."},
      "scenes": {"1": {"runtime": 6012.4, "credits": 5710,
                       "scenes": [{"start": 5788, "end": 5850.5, "kind": "mid"}]}},
      "skip": ["movie:900"],
      "skip_titles": ["Example Saga: Behind the Scenes"],
      "drop": ["movie:901"]
    }
  ]
}
```

A universe:

| Key | Meaning |
| --- | --- |
| `name` | Required. The collection's name in Jellyfin. |
| `story` | The titles in story order (see below). |
| `wikidata` | Optional. A Wikidata item id (`"Q12345"`) or a list of them: the film series. Its parts that have a TMDb id are added after the story. |
| `groups` | Chapters: chapter name → list of titles. (`chapters` works too.) |
| `latest` | The chapter for titles in no chapter, such as new ones from Wikidata. |
| `mini` | TMDb ids of series whose season and cut stops each open as a mini series. |
| `previously` | Stop title → what to remember from the stops before it. |
| `scenes` | Film TMDb id → its credits scenes (see [Credits scenes](#credits-scenes)). |
| `skip` | Titles Wikidata lists that don't belong. |
| `skip_titles` | The same, by title (case and punctuation don't matter). |
| `drop` | Titles to take out of the collection. |

A title in `groups`, `skip` and `drop` is written `"movie:<tmdb>"` or `"tv:<tmdb>"`, or as
`{"kind": "movie", "tmdb": 1}`.

A story entry:

| Key | Meaning |
| --- | --- |
| `kind` | Required. `movie` or `tv`. |
| `tmdb` | Required. The TMDb id. |
| `title` | Required. The title as in your library; used when the TMDb id doesn't match. |
| `season` | Series only: just this season, as a stop of its own. |
| `episodes` | Series only: just these episodes, as a cut: `[[season, episode], …]`. |
| `stop_title` | A season's or cut's own name. |
| `art` | A cut's poster: a file in `ART_DIR` (default: `art/` next to the config). Uploaded once. |
| `group` | The entry's chapter. On a season or cut, only that stop's. |
| `previously` | The recap for this stop. Same as the universe's `previously`. |

A series can appear more than once: one entry per season or cut, each where it falls in the
story. The recap of a season or cut is keyed by its `stop_title`, so give each one a name.

To change the order later, edit the config. The next run moves the tags. A title that is
no longer on the path is taken out of the collection.

To swap a cut's poster, replace the file and delete the episode's Box image in Jellyfin. The
next run uploads the new one.

## Credits scenes

Finding credits scenes is done by eye, with help from `server/credits-scenes.py`. It needs
podman or docker (it uses the ffmpeg in Jellyfin's image), or ffmpeg itself. See
[server/README.md](../server/README.md) for its settings.

1. Make contact sheets: one image per film, a frame every 4 seconds from just before the
   credits to the end.

   ```sh
   MEDIA_DIR=/data/media python3 server/credits-scenes.py --config universes.json sheets
   ```

   This covers every film in your universes. Use `--item <id>` (repeatable) for just some.
   The sheets and an `index.json` go to `./credits-sheets` (or `$OUT`).

2. Look at the sheets and note roughly where each scene starts and ends. Write them down in
   a file, using `runtime` and `credits` from `index.json`:

   ```json
   {"1": {"runtime": 6012.4, "credits": 5710,
          "scenes": [{"start": 5790, "end": 5850, "kind": "mid"},
                     {"start": 5960, "end": 6012.4, "kind": "post", "spoiler": true}]}}
   ```

   Need a closer look? `credits-scenes.py sheet <film> <from> <seconds>` makes one more sheet.

3. Snap the rough times to the nearest cut or fade to black:

   ```sh
   python3 server/credits-scenes.py snap-all rough.json scenes.json
   ```

   Or one film at a time: `credits-scenes.py snap <film> 5790 5850`.

4. Paste what's in `scenes.json` into the universe's `scenes` in your config. The next run
   of `universes.py` writes them to the films.

`<film>` is a TMDb id or a Jellyfin item id. The credits are taken to start at the film's
first "Outro" media segment (from a plugin such as Intro Skipper), else at a chapter with
"credits" in its name, else 12 minutes before the end.

If a film's file changes (a new version, a different cut), its runtime no longer matches.
`universes.py` then leaves its scenes off and tells you to measure again.

## Posters

Two scripts in `server/art/` make posters in the style of the app's universe pages. They
need Pillow and the Lato font (or any font, with `--font`).

A collection poster, from up to 9 posters in a 3×3 grid:

```sh
python3 server/art/make_grid_poster.py example-saga.jpg "Example Saga" "The complete story" \
    "3 films · 1 series" 2a9d8f poster1.jpg poster2.jpg poster3.jpg ...
```

Upload it as the collection's poster in Jellyfin (Edit images).

A cut's poster, from a landscape episode still:

```sh
python3 server/art/make_cut_poster.py still.jpg example-saga-the-lost-map.jpg \
    "Example Saga: The Series" "The Lost Map" "Season 2 · Episodes 1-2" "A side story" 0.4 2a9d8f
```

The `0.4` is where to crop the still (0 is the left edge, 1 the right). Put the result in
`ART_DIR` and name it in the cut's `art`.
