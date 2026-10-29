# Building Hevyfin

Hevyfin has **no ready-made downloads**: you build it yourself from this source code. It's
free, and you don't need to know how to program. Follow the steps for the device you want.
The first build takes about half an hour (mostly downloads); later ones take a few minutes.

Hevyfin is one Flutter app (Linux, Android, Android TV, web) plus a separate Vue browser version
(`browser/`) and an admin panel (`admin/`).

## 1. Get the tools (once)

You build on a **Linux** computer (Windows and macOS can build the Android app too: follow
Flutter's guide for your system in step 1b).

**a. Git**, to download the code: `sudo dnf install git` (Fedora), `sudo apt install git`
(Debian/Ubuntu), `sudo pacman -S git` (Arch).

**b. Flutter**: follow <https://docs.flutter.dev/get-started/install> ("Linux", then "Android"
if you want the phone/TV app). You need Flutter **3.47 or newer** (`flutter --version`).
When it's set up, `flutter doctor` lists what's still missing; fix what it says for the
platform you want (you can ignore the others).

**c. Android only: the Android SDK and Java 17.** The easiest way is
[Android Studio](https://developer.android.com/studio): install it, open it once, let it download
the SDK, then run:

```sh
flutter doctor --android-licenses     # accept them all with y
```

## 2. Get the code (once)

```sh
git clone https://github.com/NickHemeryckeHevan/hevyfin.git
cd hevyfin
flutter pub get
flutter test            # optional: checks everything works (no server needed)
```

To update later: `git pull && flutter pub get`, then build again.

## Linux (x86_64)

Install the build packages and **libmpv** (the video player) with its development files:

```sh
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel mpv-devel     # Fedora
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev          # Debian / Ubuntu
sudo pacman -S clang cmake ninja pkgconf gtk3 mpv                                     # Arch
```

Then:

```sh
flutter run -d linux                  # try it
./scripts/install-linux.sh            # install it: ~/.local/opt/hevyfin + a menu entry
```

`install-linux.sh` copies libmpv and a few libraries an immutable distro (Silverblue, Bazzite…)
may lack into the app's folder, so you can build in a toolbox/distrobox and run it on the host.

## Android (phones, tablets and TV)

### Build the APK

```sh
flutter build apk --release --split-per-abi
```

This makes a few APK files in `build/app/outputs/flutter-apk/`. Almost every phone, tablet and
TV from the last years needs **`app-arm64-v8a-release.apk`**. (Very old or cheap devices may need
`app-armeabi-v7a-release.apk`.)

### Put it on a phone or tablet

- **With a cable**: switch on *Developer options* on the phone (Settings → About phone → tap
  *Build number* 7 times), then *USB debugging*. Connect it and run
  ```sh
  adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
  ```
  (`adb` comes with the Android SDK, in `~/Android/Sdk/platform-tools/`).
- **Without a cable**: copy the APK to the phone (cloud drive, e-mail to yourself, USB) and
  tap it there. Android asks you to allow installing apps from that source: allow it once.

### Put it on an Android TV / Google TV

1. On the TV: Settings → System → About → click *Android TV OS build* 7 times to switch on
   *Developer options*; then Settings → System → Developer options → switch on *USB debugging*
   (on Google TV also *Wireless debugging* if you see it).
2. Find the TV's IP address (Settings → Network & Internet → your network).
3. On your computer:
   ```sh
   adb connect 192.168.1.50:5555          # your TV's address
   adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```
   The TV asks once to allow your computer: choose *Always allow*.

Hevyfin then shows up in the TV's apps row. Sign in with the code shown on screen from Hevyfin on
your phone (Settings → Sign in a TV) or from Jellyfin (Quick Connect), or with your password.

### Updates and your signing key

Android only installs an update over the old app if both were **signed with the same key**.

- **Simplest**: do nothing. Without a key of your own, builds are signed with your computer's
  *debug key* (in `~/.android/debug.keystore`). Updates built on **the same computer** install
  fine. Build on another computer, and you must uninstall the old app first (and sign in again).
- **Your own key**, so you can build updates anywhere: make one once,

  ```sh
  keytool -genkey -v -keystore ~/.android/hevyfin-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hevyfin
  ```

  and create `android/key.properties` (it's in `.gitignore`: **never commit it or share it**):

  ```properties
  storeFile=/home/you/.android/hevyfin-release.jks
  storePassword=…
  keyAlias=hevyfin
  keyPassword=…
  ```

  Keep a backup of the `.jks` file and its passwords: without them, no update will install over
  the app.

### Sharing the app with your household

If you host the web version, phones that open it get a download page. Put your APK there
([self-hosting-web.md](self-hosting-web.md#phones-get)). Please don't publish your builds as
"official" Hevyfin downloads; if you share builds, the GPL asks you to share the source with them
(a link to this repository, plus your changes if you made any).

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
