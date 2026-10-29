# Building Hevyfin

Hevyfin is one Flutter app (Linux, Android, Android TV, web) plus a separate Vue browser version
(`browser/`) and an admin panel (`admin/`). You need [Flutter](https://docs.flutter.dev/get-started/install)
stable (3.47 or newer; Dart 3.13+), Node.js 22+ for the Vue parts, and Python 3.12 for the admin backend.

```sh
git clone https://github.com/NickHemeryckeHevan/hevyfin.git && cd hevyfin
flutter pub get
flutter test            # unit tests, no server needed
```

## Linux (x86_64)

Needs the usual Flutter Linux packages (clang, cmake, ninja, pkg-config, GTK 3 headers) and **libmpv**
with its headers: `mpv-devel` (Fedora), `libmpv-dev` (Debian/Ubuntu), `mpv` (Arch).

```sh
flutter run -d linux                  # try it
./scripts/install-linux.sh            # release build in ~/.local/opt/hevyfin + a menu entry
```

`install-linux.sh` copies libmpv and a few libraries an immutable distro (Silverblue, Bazzite…)
may lack into the bundle, so you can build in a toolbox/distrobox and run it on the host.

## Android and Android TV

Needs the Android SDK (Android Studio, or the command-line tools) and Java 17.

```sh
flutter build apk --release --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The same APK runs on phones, tablets and Android TV / Google TV (it has a leanback launcher entry).

**Signing.** Without a key, release builds are signed with the debug key: fine for yourself,
but you can't update them with a build from another machine. For your own key:

```sh
keytool -genkey -v -keystore ~/.android/hevyfin-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hevyfin
```

and create `android/key.properties` (it's in `.gitignore`: **never commit it**):

```properties
storeFile=/home/you/.android/hevyfin-release.jks
storePassword=…
keyAlias=hevyfin
keyPassword=…
```

Keep a backup of the keystore somewhere safe: without it you can't publish updates that
install over the old app.

## Web (Flutter build)

```sh
flutter build web --release --no-web-resources-cdn
```

The web build expects to be served by `server/web/` (it reaches Jellyfin at `/jellyfin` on its
own address). See [self-hosting-web.md](self-hosting-web.md). `scripts/deploy-web.sh` builds it and
copies it to your server.

## Browser version (Vue, `browser/`)

A lighter browser version for computers (Firefox, Chrome): about 60 KB for the first page
instead of the Flutter build's 3.5 MB. It has no Cinema mode, Watch together / Play on TV, Live TV,
marathons or downloads.

```sh
cd browser
npm ci
npm test
JELLYFIN_URL=http://jellyfin.local:8096 SEERR_URL=http://jellyfin.local:5055 npm run dev   # http://localhost:5199/next/
npm run build             # dist/, for /next/ (HEVYFIN_BASE=/ builds it for the root)
```

## Admin panel (`admin/`)

```sh
cd admin/frontend && npm ci && npm run dev          # http://localhost:5198, API on :5000
cd admin/backend && pip install -r requirements.txt
SECRET_KEY=dev JELLYFIN_URL=http://jellyfin.local:8096 flask --app hevyfin_admin.wsgi run
podman build -t localhost/hevyfin-admin:dev admin/  # or docker build
```

See [admin.md](admin.md).

## Build-time options

| Option | What it does |
|---|---|
| `--dart-define=NIQL_URL=…` | Default address of the optional recommendation service ([niql.md](niql.md)). |
| `--dart-define=SAVER_SECONDS=30` | Start the TV screensaver after 30 s instead of 5 min (testing). |
| `HEVYFIN_ROUTE=/item/<id>` (env) | Open the app straight on a page (`/play/<id>` plays it). |
| `VITE_NIQL_URL=/niql` (env, Vue) | Turn on "Ask" in the browser version. |

## Integration tests

`integration_test/` drives the real app against **the server you're signed in to** (sign in once
in the app first). Some write to it (watch progress, settings), so use a test server or a test user.

```sh
flutter test integration_test/tour_test.dart -d linux --dart-define=SHOTS=/tmp/shots \
  --dart-define=SHOT_CMD="gnome-screenshot -w -f"     # or spectacle -b -n -a -o (KDE, the default)
```
