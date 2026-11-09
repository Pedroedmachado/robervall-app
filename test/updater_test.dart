import 'dart:convert';
import 'dart:io';

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
    expect(s, contains(r"robocopy 'C:\Temp\novo' 'C:\Users\Zé d''Oficina\Funilar' /E"));
    expect(s, contains('funilar-atualizacao.log'));
    expect(windowsSwapScript(pid: 1, from: 'a', to: 'b', tag: 't', relaunch: false),
        isNot(contains('Start-Process')));
    expect(s, contains(r"'C:\Users\Zé d''Oficina\Funilar'"));
    expect(s, contains("'v1.0.60'"));
    expect(s, contains('funilar.exe'));
  });

  test('Linux: baixa o .tar.gz, troca os arquivos e grava a versão', () async {
    if (!Platform.isLinux) return;
    final src = await Directory.systemTemp.createTemp('funilar_src');
    await File('${src.path}/bundle/funilar').create(recursive: true);
    await File('${src.path}/bundle/funilar').writeAsString('novo');
    await File('${src.path}/bundle/data/flutter_assets/a.txt').create(recursive: true);
    final made = await Process.run('tar', ['-C', src.path, '-czf', '${src.path}/x.tar.gz', 'bundle']);
    expect(made.exitCode, 0);
    final tgz = await File('${src.path}/x.tar.gz').readAsBytes();
    final install = await Directory.systemTemp.createTemp('funilar_inst');
    await File('${install.path}/funilar').writeAsString('velho');
    final script = await prepareLinuxUpdate(
      const ReleaseInfo('v1.0.200', '', {}),
      tarGzBytes: tgz,
      installDir: install.path,
      waitPid: 999999,
      relaunch: false,
    );
    expect(await script.readAsString(), contains('cp -a'));
    final r = await Process.run('sh', [script.path]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(await File('${install.path}/funilar').readAsString(), 'novo');
    expect(await File('${install.path}/data/flutter_assets/a.txt').exists(), isTrue);
    expect((await File('${install.path}/versao.txt').readAsString()).trim(), 'v1.0.200');
  });
}
