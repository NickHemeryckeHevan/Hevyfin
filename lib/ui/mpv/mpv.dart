/// mpv's own properties (languages, subtitle look, audio passthrough). The apps play with
/// mpv; the web version plays in the browser's `<video>`, where these do nothing.
library;

export 'mpv_native.dart' if (dart.library.js_interop) 'mpv_web.dart';
