# "Ask": plug in your own recommendation service

**What tonight?** (Search → What should I watch tonight?) always offers **Surprise me**: you
pick what, how long, a mood and who's watching, and it suggests three titles from your
library, all inside the app.

It can also take questions in your own words ("something funny we haven't seen, under two
hours") and send them to a **recommendation service you run yourself**, for example a small
script that asks a language model. That part is **off** until you give it an address,
because every question is sent with the user's Jellyfin sign-in (so the service can check who
is asking and what they may watch).

(In the code it's called "Niql", the name of the original author's own service.)

## Turning it on

- **Apps** (Linux, Android, TV): Settings → **Ask (optional)** → *Recommendation service
  address*, e.g. `http://my-server:8050`. Leave it empty to hide Ask again.
  A build can also have a default: `flutter build … --dart-define=NIQL_URL=http://my-server:8050`.
- **Web**: the browser can only reach it through the web server. Set `NIQL_UPSTREAM` when you
  run `server/web/install.sh` (nginx then passes `/niql/` on), and build with
  `--dart-define=NIQL_URL=/niql` (Flutter web, `NIQL_URL=/niql scripts/deploy-web.sh`) or
  `VITE_NIQL_URL=/niql` (Vue browser version).

## The API

One endpoint. Answers may take a while: the apps wait up to 120 seconds.

```
POST {address}/api/hevyfin/ask
Content-Type: application/json
X-Emby-Token: <the user's Jellyfin access token>

{"text": "something funny we haven't seen, under two hours"}
```

Answer with `200`:

```json
{
  "answer": "Two short comedies you haven't seen, and one you loved last year.",
  "picks": [
    {"id": "<Jellyfin item id>", "why": "Short, silly, and everyone's in it."},
    {"id": "<Jellyfin item id>", "why": "A comedy of errors at a wedding."}
  ]
}
```

- `answer`: one line shown above the picks.
- `picks`: up to three Jellyfin item ids from the user's library, each with a short reason.
  Ids the user can't see are left out.
- On an error, answer with any non-200 status and `{"error": "what went wrong"}`: the app shows it.

### Checking the token

Call Jellyfin with the token you were given, so you know who's asking and only pick from
what they may see:

```sh
curl -H "X-Emby-Token: $TOKEN" http://jellyfin:8096/Users/Me
curl -H "X-Emby-Token: $TOKEN" "http://jellyfin:8096/Items?Recursive=true&IncludeItemTypes=Movie,Series&Fields=Genres,Overview"
```

Never log or store the token. Keep the service on your LAN or VPN.
