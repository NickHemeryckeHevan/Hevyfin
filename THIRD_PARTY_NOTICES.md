# Third-party notices

Hevyfin is licensed under the GNU GPL v3 or later ([LICENSE](LICENSE)). It includes or uses the
following third-party work, under their own licenses.

## Included in this repository

| What | Where | License |
|---|---|---|
| **media_kit_video** 2.0.1, © 2021 & onwards Hitesh Kumar Saini | `third_party/media_kit_video/` | MIT, see `third_party/media_kit_video/LICENSE` |
| **Roboto** Medium (subtitle font), © Google, designed by Christian Robertson | `assets/fonts/subtitle.ttf` | Apache License 2.0, see `assets/fonts/LICENSE-Roboto.txt` |

**Change to media_kit_video:** the vendored copy differs from the pub.dev 2.0.1 release in one
place: `linux/texture_gl.cc` passes `MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 0` to mpv's render
call, so mpv no longer blocks Flutter's raster thread on Linux. `pubspec.yaml` points
`dependency_overrides` at this copy.

The sound `assets/live/sting.ogg` was made for this project (synthesised with ffmpeg) and
is under the project's license.

## Used at build or run time (not included)

| What | License |
|---|---|
| Flutter and the Dart packages in `pubspec.yaml` (media_kit, go_router, provider, http, shared_preferences, google_fonts, …) | BSD-3-Clause / MIT / Apache-2.0, see `flutter pub deps` and each package |
| **libmpv** / mpv (bundled by `scripts/install-linux.sh` and the media_kit_libs packages) | LGPL-2.1-or-later (GPL-2.0-or-later when built with GPL parts) |
| **Inter Tight** (UI font, fetched by google_fonts / @fontsource) | SIL Open Font License 1.1 |
| **Vue**, **vue-router**, **Vite** (browser version, admin page) | MIT |
| **hls.js** (browser version) | Apache-2.0 |
| **blurhash** (browser version) | MIT |
| **Flask**, **gunicorn**, **requests** (admin backend) | BSD-3-Clause / MIT / Apache-2.0 |
| **nginx** (web hosting container) | BSD-2-Clause |
| **yt-dlp** (optional server scripts, run in its own container) | Unlicense |

If you distribute builds, include this file and the license files above with them.
