import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

import '../api/jellyfin.dart';
import '../theme.dart';
import 'widgets/common.dart' show isNarrow;

/// The web version's player helpers. A browser's `<video>` plays only a file's default
/// audio track and media_kit's web subtitles are unreliable, so the server sends the
/// chosen audio (see [JellyfinClient.playbackInfo]) and Hevyfin draws text subtitles itself.

/// One line of subtitles and when it shows.
class Cue {
  final Duration start, end;
  final String text;
  const Cue(this.start, this.end, this.text);
}

final _time = RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})');

Duration? _parseTime(String s) {
  final m = _time.firstMatch(s);
  if (m == null) return null;
  return Duration(
    hours: int.tryParse(m.group(1) ?? '') ?? 0,
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: int.parse(m.group(4)!),
  );
}

/// The cues of a WebVTT (or SRT) file, in order, with styling tags taken out.
List<Cue> parseVtt(String body) {
  final cues = <Cue>[];
  final blocks = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n\s*\n'));
  for (final b in blocks) {
    final lines = b.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final at = lines.indexWhere((l) => l.contains('-->'));
    if (at < 0) continue;
    final parts = lines[at].split('-->');
    final start = _parseTime(parts[0]), end = _parseTime(parts[1]);
    if (start == null || end == null) continue;
    final text = lines
        .skip(at + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
    if (text.isNotEmpty) cues.add(Cue(start, end, text));
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

Future<List<Cue>> loadCues(String url) async {
  final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) throw 'Subtitles unavailable (${res.statusCode})';
  return parseVtt(res.body);
}

/// The subtitle line for the player's position.
class CueOverlay extends StatelessWidget {
  final Player player;
  final List<Cue> cues;
  final TextStyle style;
  final EdgeInsets padding;
  const CueOverlay({super.key, required this.player, required this.cues, required this.style, required this.padding});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, _) {
        final p = player.state.position;
        final text = [
          for (final c in cues)
            if (c.start <= p && c.end > p) c.text,
        ].join('\n');
        return Padding(
          padding: padding,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: text.isEmpty ? const SizedBox.shrink() : Text(text, textAlign: TextAlign.center, style: style),
          ),
        );
      },
    ),
  );
}

/// Audio and subtitle picker for the web version, from the server's list of tracks.
class WebTracksSheet extends StatelessWidget {
  final PlaybackInfo info;

  /// The audio track playing, and the subtitle showing (null for none).
  final int? audio, subtitle;
  final void Function(MediaStream s) onAudio;
  final void Function(MediaStream? s) onSubtitle;
  const WebTracksSheet({super.key, required this.info, this.audio, this.subtitle, required this.onAudio, required this.onSubtitle});

  @override
  Widget build(BuildContext context) {
    final audios = info.streams.where((s) => s.type == 'Audio').toList();
    final subs = info.streams.where((s) => s.type == 'Subtitle').toList();

    Widget option(String label, bool selected, VoidCallback onTap) => ListTile(
      dense: true,
      autofocus: selected,
      onTap: () {
        Navigator.pop(context);
        if (!selected) onTap();
      },
      leading: Icon(selected ? Icons.check_rounded : null, color: Hy.orange),
      title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
    );

    Widget column(String title, List<Widget> options) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        ...options,
      ],
    );

    final audioCol = column('Audio', [for (final a in audios) option(a.title, a.index == audio, () => onAudio(a))]);
    final subCol = column('Subtitles', [
      option('Off', subtitle == null, () => onSubtitle(null)),
      for (final s in subs) option(s.title, s.index == subtitle, () => onSubtitle(s)),
    ]);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: isNarrow(context)
              ? Column(children: [audioCol, const SizedBox(height: 12), subCol])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: audioCol),
                    Expanded(child: subCol),
                  ],
                ),
        ),
      ),
    );
  }
}
