import 'package:flutter/material.dart';

import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/live_bumpers.dart';
import 'live_player.dart' show tickets;

/// Every showing sat through to the end, newest first, as ticket stubs.
class TicketsPage extends StatelessWidget {
  const TicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final top = MediaQuery.paddingOf(context).top + (isNarrow(context) ? 70 : 90);
    final scale = isNarrow(context) ? (MediaQuery.sizeOf(context).width - pad * 2) / 620 : .8;
    return Loader<List<Map<String, dynamic>>>(
      load: () => tickets(jf(context)),
      builder: (context, list) => ListView(
        padding: EdgeInsets.fromLTRB(pad, top, pad, 120),
        children: [
          const Text('Ticket stubs', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
            list.isEmpty ? 'Watch a film in Cinema mode to the end and its stub lands here.' : '${list.length} showing${list.length == 1 ? '' : 's'} so far',
            style: const TextStyle(color: Hy.textDim),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final t in list.reversed)
                TicketStub(title: '${t['title']}', when: DateTime.parse('${t['when']}'), seat: '${t['seat']}', scale: scale.clamp(.4, 1.0)),
            ],
          ),
        ],
      ),
    );
  }
}
