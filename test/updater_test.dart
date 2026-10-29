import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('compara versões', () {
    expect(isNewer('v1.0.49', 'v1.0.48'), isTrue);
    expect(isNewer('v1.0.48', 'v1.0.48'), isFalse);
    expect(isNewer('v1.0.47', 'v1.0.48'), isFalse);
    expect(isNewer('v1.0.100', 'v1.0.99'), isTrue);
    expect(isNewer('v1.1.0', 'v1.0.99'), isTrue);
    expect(isNewer('v1.0.1', 'dev'), isTrue);
  });

  test('lê a última versão do GitHub', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/repos/Pedroedmachado/robervall-app/releases/latest');
      return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.60',
            'body': 'Novidades',
            'assets': [
              {'name': 'Funilar-windows-x64.zip', 'browser_download_url': 'https://x/w.zip', 'size': 123},
              {'name': 'Funilar-android.apk', 'browser_download_url': 'https://x/a.apk', 'size': 456},
            ],
          }),
          200);
    });
    final r = await fetchLatestRelease(client: client);
    expect(r.tag, 'v1.0.60');
    expect(r.asset('Funilar-windows-x64.zip'), ('https://x/w.zip', 123));
    expect(r.asset('Funilar-android.apk')!.$2, 456);
  });

  test('script do Windows espera o app fechar, copia e reabre', () {
    final s = windowsSwapScript(
        pid: 4242, from: r"C:\Temp\novo", to: r"C:\Users\Zé d'Oficina\Funilar", tag: 'v1.0.60');
    expect(s, contains('Wait-Process -Id 4242'));
    expect(s, contains(r"Copy-Item -Path (Join-Path 'C:\Temp\novo' '*')"));
    expect(s, contains(r"'C:\Users\Zé d''Oficina\Funilar'"));
    expect(s, contains("'v1.0.60'"));
    expect(s, contains('funilar.exe'));
  });
}
