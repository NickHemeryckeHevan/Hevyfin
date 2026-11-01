import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';

/// TV: Hevyfin's own on-screen keyboard. On a Chromecast with Google TV, Gboard does come up over
/// a Flutter text field, but Android never links it to the app (InputMethodManager "Ignoring
/// onBind"), so the remote's keys went to the app and typing needed the Google Home app. This one
/// is ours: OK on a text field opens it at the bottom of the screen, the remote moves over the
/// keys, and what's typed goes straight into the field (search runs as you type).
abstract final class TvKeyboard {
  /// With our own input control installed, Flutter tells Android the fields take no on-screen
  /// keyboard, so Gboard stays away. A keyboard plugged into the TV still types as before.
  static void install() => TextInput.setInputControl(_NoSystemKeyboard());

  static bool _open = false;

  static Future<void> open(EditableTextState field) async {
    if (_open || !field.mounted) return;
    _open = true;
    try {
      await showGeneralDialog<void>(
        context: field.context,
        barrierDismissible: true,
        barrierLabel: 'Close the keyboard',
        barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, _, _) => _Panel(field: field),
        transitionBuilder: (_, a, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: a, child: child),
        ),
      );
    } finally {
      _open = false;
    }
  }
}

class _NoSystemKeyboard with TextInputControl {}

const _letters = ['1234567890', 'qwertyuiop', "asdfghjkl'", 'zxcvbnm,.-'];
const _symbols = ['1234567890', '@#\$%&*()_+', '!?:;/\\|"=~', '<>[]{}^`,.'];

class _Panel extends StatefulWidget {
  const _Panel({required this.field});
  final EditableTextState field;
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool _shift = false, _symbolsUp = false;

  EditableText get _w => widget.field.widget;
  String get _text => widget.field.textEditingValue.text;

  @override
  void initState() {
    super.initState();
    _w.controller.addListener(_changed);
  }

  @override
  void dispose() {
    _w.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Typed at the end, through the field's own formatters and onChanged.
  void _set(String text) {
    if (!widget.field.mounted) return;
    widget.field.userUpdateTextEditingValue(
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
      SelectionChangedCause.keyboard,
    );
  }

  void _type(String s) {
    _set(_text + s);
    if (_shift) setState(() => _shift = false);
  }

  void _back() => _set(_text.characters.skipLast(1).toString());

  TextInputAction get _action => _w.textInputAction ?? (_w.maxLines == 1 ? TextInputAction.done : TextInputAction.newline);

  /// Done / Search / Next: what the phone keyboard's action key does. Next moves on to the
  /// following field and opens the keyboard there too.
  void _done() {
    final field = widget.field, action = _action;
    Navigator.of(context).pop();
    if (action == TextInputAction.newline) {
      _set('$_text\n');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!field.mounted) return;
      if (action == TextInputAction.next || action == TextInputAction.previous) {
        field.widget.focusNode.requestFocus();
        field.performAction(action);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final next = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
          if (next != null && next != field) TvKeyboard.open(next);
        });
      } else {
        // The field keeps the remote, so up/down carry on from where you typed.
        field.widget.onEditingComplete?.call();
        field.widget.onSubmitted?.call(field.textEditingValue.text);
      }
    });
  }

  /// A keyboard plugged into the TV types here too while this is open.
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _done();
      return KeyEventResult.handled;
    }
    final c = e.character;
    if (c != null && c.isNotEmpty && c.codeUnitAt(0) >= 32 && c.codeUnitAt(0) != 127) {
      _set(_text + c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _actionLabel => switch (_action) {
    TextInputAction.search => 'Search',
    TextInputAction.next => 'Next',
    TextInputAction.go => 'Go',
    TextInputAction.send => 'Send',
    TextInputAction.newline => 'New line',
    _ => 'Done',
  };

  @override
  Widget build(BuildContext context) {
    final deco = widget.field.context.findAncestorWidgetOfExactType<TextField>()?.decoration;
    final label = deco?.labelText ?? deco?.hintText ?? '';
    final text = _w.obscureText ? '•' * _text.characters.length : _text;
    final rows = _symbolsUp ? _symbols : _letters;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Focus(
        onKeyEvent: _key,
        skipTraversal: true,
        child: Material(
          color: Hy.surface,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // What's typed so far, also when the field itself is behind the keyboard.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Hy.bg, borderRadius: BorderRadius.circular(Hy.radius), border: Border.all(color: Hy.border)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (text.isEmpty) TextSpan(text: label, style: const TextStyle(color: Hy.textMute)) else TextSpan(text: text),
                                const TextSpan(text: '▏', style: TextStyle(color: Hy.orange)),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final (i, row) in rows.indexed)
                    Row(
                      children: [
                        for (final (j, ch) in row.characters.indexed)
                          _Key(
                            label: _shift ? ch.toUpperCase() : ch,
                            autofocus: i == 1 && j == 0,
                            onTap: () => _type(_shift ? ch.toUpperCase() : ch),
                          ),
                      ],
                    ),
                  Row(
                    children: [
                      _Key(
                        icon: _shift ? Icons.keyboard_capslock_rounded : Icons.keyboard_arrow_up_rounded,
                        tooltip: 'Capital letter',
                        lit: _shift,
                        flex: 2,
                        onTap: () => setState(() => _shift = !_shift),
                      ),
                      _Key(label: _symbolsUp ? 'abc' : '?#@', flex: 2, onTap: () => setState(() => _symbolsUp = !_symbolsUp)),
                      _Key(icon: Icons.space_bar_rounded, tooltip: 'Space', flex: 4, onTap: () => _type(' ')),
                      _Key(icon: Icons.backspace_outlined, tooltip: 'Delete', flex: 2, onTap: _back),
                      _Key(label: 'Clear', flex: 2, onTap: () => _set('')),
                      _Key(label: _actionLabel, flex: 3, accent: true, onTap: _done),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One key: white with black text under the remote, like the rest of the TV interface.
class _Key extends StatefulWidget {
  const _Key({this.label, this.icon, this.tooltip, required this.onTap, this.flex = 1, this.accent = false, this.lit = false, this.autofocus = false});
  final String? label, tooltip;
  final IconData? icon;
  final VoidCallback onTap;
  final int flex;
  final bool accent, lit, autofocus;
  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? Colors.white
        : widget.accent
        ? Hy.orange
        : widget.lit
        ? Hy.active
        : Hy.surfaceHigh;
    final fg = _focused || widget.accent ? Colors.black : Hy.text;
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FocusableActionDetector(
          autofocus: widget.autofocus,
          onFocusChange: (f) => setState(() => _focused = f),
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(Hy.radius),
                border: _focused ? Border.all(color: Hy.orange, width: 3) : null,
              ),
              child: widget.icon != null
                  ? Icon(widget.icon, color: fg, size: 26, semanticLabel: widget.tooltip)
                  : Text(widget.label ?? '', style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}
