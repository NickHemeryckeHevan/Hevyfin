import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'common.dart';

/// TV's Live page holds both the channels and the cinema: this switches between them.
class LiveSwitch extends StatelessWidget {
  final String current;
  const LiveSwitch(this.current, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (path, label) in const [('/tv', 'Channels'), ('/cinema', 'Cinema')])
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Pill(label: label, selected: current == path, onTap: () => current == path ? null : context.go(path)),
        ),
    ],
  );
}
