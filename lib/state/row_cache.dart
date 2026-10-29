import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin.dart';

/// The last Home rows on disk, so the app opens onto them straight away (the TV's network
/// and CPU make a cold load take seconds) while fresh ones load behind. In a browser they
/// go in its local storage instead.
abstract final class RowCache {
  static Map<String, List<Map<String, dynamic>>> _rows = {};
  static File? _file;
  static SharedPreferences? _prefs;
  static String _user = '';
  static Timer? _save;

  static Future<void> load(String userId) async {
    _user = userId;
    try {
      final String? raw;
      if (kIsWeb) {
        _prefs = await SharedPreferences.getInstance();
        raw = _prefs!.getString('rows_$userId');
      } else {
        _file = File('${(await getApplicationSupportDirectory()).path}/rows_$userId.json');
        raw = await _file!.exists() ? await _file!.readAsString() : null;
      }
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _rows = {for (final e in j.entries) e.key: (e.value as List).cast<Map<String, dynamic>>()};
      }
    } catch (_) {
      _rows = {};
    }
  }

  static List<Item>? get(String key, String userId) => userId == _user ? _rows[key]?.map(Item.new).toList() : null;

  static void put(String key, String userId, List<Item> items) {
    if (userId != _user || (_file == null && _prefs == null)) return;
    _rows[key] = [for (final i in items.take(30)) i.raw];
    _save?.cancel();
    _save = Timer(const Duration(seconds: 3), () {
      final json = jsonEncode(_rows);
      if (_prefs != null) {
        _prefs!.setString('rows_$_user', json).catchError((_) => false);
      } else {
        _file?.writeAsString(json).catchError((_) => _file!);
      }
    });
  }
}
