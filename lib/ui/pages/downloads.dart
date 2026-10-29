import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/downloads.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// What's saved on this device for offline viewing, and how much of the 10 GB it takes.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<Downloads>();
    final pad = pagePadding(context);
    final top = MediaQuery.paddingOf(context).top + (isNarrow(context) ? 70 : 90);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, top, pad, 120),
      children: [
        const Text('Downloads', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        _Usage(used: dl.used, reserved: dl.reserved),
        const SizedBox(height: 22),
        if (dl.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.download_for_offline_outlined, size: 64, color: Hy.textMute),
                SizedBox(height: 14),
                Text('Nothing downloaded yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  'Use the download button on a movie or an episode to watch it without a connection.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Hy.textDim),
                ),
              ],
            ),
          )
        else
          for (final d in dl.items.reversed) _Row(d),
      ],
    );
  }
}

class _Usage extends StatelessWidget {
  final int used, reserved;
  const _Usage({required this.used, required this.reserved});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          children: [
            Container(height: 8, color: Colors.white12),
            FractionallySizedBox(
              widthFactor: (reserved / Downloads.limit).clamp(0, 1),
              child: Container(height: 8, color: Hy.orange.withValues(alpha: .35)),
            ),
            FractionallySizedBox(
              widthFactor: (used / Downloads.limit).clamp(0, 1),
              child: Container(height: 8, color: Hy.orange),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text('${gb(used)} of ${gb(Downloads.limit)} used on this device', style: const TextStyle(color: Hy.textDim, fontSize: 13)),
    ],
  );
}

class _Row extends StatelessWidget {
  final Download d;
  const _Row(this.d);

  @override
  Widget build(BuildContext context) {
    final dl = context.read<Downloads>();
    final pct = d.total > 0 ? (d.bytes / d.total).clamp(0.0, 1.0) : null;
    final status = switch (d.status) {
      'done' => '${d.quality.label} · ${gb(d.total)}',
      'downloading' => '${gb(d.bytes)}${d.total > 0 ? ' of ~${gb(d.total)}' : ''}',
      'failed' => "Didn't finish: ${d.error ?? 'unknown error'}",
      _ => 'Waiting · ${d.quality.label}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HoverScale(
        scale: 1.01,
        onTap: d.done ? () => context.push('/play/${d.id}?local=1') : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Hy.surface, borderRadius: BorderRadius.circular(Hy.radius + 2)),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Hy.radius),
                child: SizedBox(
                  width: d.episodeCode != null ? 128 : 60,
                  height: d.episodeCode != null ? 72 : 90,
                  child: FutureBuilder<File>(
                    future: dl.poster(d.id),
                    builder: (context, f) => f.data == null
                        ? const ColoredBox(color: Hy.surfaceHigh)
                        : Image.file(
                            f.data!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const ColoredBox(color: Hy.surfaceHigh),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                    if (d.subtitle.isNotEmpty)
                      Text(
                        d.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Hy.textDim),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: d.status == 'failed' ? Hy.danger : Hy.textMute, fontSize: 12.5),
                    ),
                    if (d.status == 'downloading') ...[
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: pct, minHeight: 3, color: Hy.orange, backgroundColor: Colors.white12),
                    ],
                  ],
                ),
              ),
              if (d.done) const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34),
              if (d.status == 'failed') IconButton(tooltip: 'Try again', onPressed: () => dl.retry(d.id), icon: const Icon(Icons.refresh_rounded)),
              IconButton(
                tooltip: d.done ? 'Delete download' : 'Cancel',
                onPressed: () => dl.remove(d.id),
                icon: Icon(d.done ? Icons.delete_outline_rounded : Icons.close_rounded, color: Hy.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The download button's sheet: pick a size, or see that it's already saved.
Future<void> downloadItem(BuildContext context, Item item) async {
  final dl = context.read<Downloads>();
  if (dl.of(item.id) != null) {
    context.go('/downloads');
    return;
  }
  final q = await showModalBottomSheet<DlQuality>(
    context: context,
    backgroundColor: Hy.surface,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              'Download ${item.isEpisode ? '${item.episodeCode} ${item.name}' : item.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('${gb(dl.reserved)} of ${gb(Downloads.limit)} used', style: const TextStyle(color: Hy.textDim)),
          ),
          for (final q in DlQuality.values)
            ListTile(
              leading: Icon(q == DlQuality.original ? Icons.hd_rounded : Icons.download_rounded, color: Hy.orange),
              title: Text(q.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                q == DlQuality.original ? q.hint : '${q.hint} · about ${gb(Downloads.estimate(item, q))} for this one',
                style: const TextStyle(color: Hy.textDim),
              ),
              onTap: () => Navigator.pop(c, q),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (q == null || !context.mounted) return;
  try {
    await dl.add(item, q);
    if (context.mounted) toast(context, 'Downloading ${item.name}');
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// A small download button that shows progress and turns into a tick when saved.
class DownloadIcon extends StatelessWidget {
  final Item item;
  final double size;
  const DownloadIcon(this.item, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final d = context.watch<Downloads>().of(item.id);
    return IconButton(
      tooltip: d == null ? 'Download' : (d.done ? 'Downloaded' : 'Downloading'),
      visualDensity: VisualDensity.compact,
      onPressed: () => downloadItem(context, item),
      icon: d == null
          ? Icon(Icons.download_rounded, color: Hy.textMute, size: size)
          : d.done
          ? Icon(Icons.download_done_rounded, color: Hy.orange, size: size)
          : SizedBox(
              width: size - 4,
              height: size - 4,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Hy.orange, value: d.total > 0 ? (d.bytes / d.total).clamp(0, 1) : null),
            ),
    );
  }
}
