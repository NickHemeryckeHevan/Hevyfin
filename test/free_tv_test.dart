import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/state/free_tv.dart';

void main() {
  const master = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6128000,RESOLUTION=1920x1080
hd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=14000000,RESOLUTION=3840x2160
uhd/index.m3u8
''';

  test('picks the best quality under the cap, as an absolute address', () {
    expect(FreeTv.bestVariant('https://cdn.example/live/master.m3u8', master), 'https://cdn.example/live/hd/index.m3u8');
  });

  test('falls back to the smallest when all are over the cap', () {
    expect(FreeTv.bestVariant('https://cdn.example/m.m3u8', master, cap: 100000), 'https://cdn.example/low/index.m3u8');
  });

  test('a plain media playlist is played as it is', () {
    expect(FreeTv.bestVariant('https://cdn.example/m.m3u8', '#EXTM3U\n#EXTINF:6,\nseg1.ts\n'), isNull);
  });
}
