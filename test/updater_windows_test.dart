// Teste de verdade da atualização no Windows (roda no GitHub Actions, numa
// máquina Windows, com o .zip gerado na mesma compilação).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/updater.dart';

void main() {
  final zipPath = Platform.environment['FUNILAR_ZIP'] ?? '';
  final skip = !Platform.isWindows || zipPath.isEmpty
      ? 'só no Windows do CI (FUNILAR_ZIP)'
      : null;

  test('troca os arquivos de uma instalação antiga e grava a versão', () async {
    final bytes = await File(zipPath).readAsBytes();
    final install = await Directory.systemTemp.createTemp('fn_instalado');
    // instalação "antiga": exe falso e um arquivo de dados que deve ficar
    await File('${install.path}\\funilar.exe').writeAsString('versao velha');
    await File('${install.path}\\data\\flutter_assets\\velho.txt')
        .create(recursive: true);
    // processo que "é o app": o script espera ele fechar
    final fake = await Process.start(
        'powershell.exe', ['-NoProfile', '-Command', 'Start-Sleep -Seconds 3']);
    final script = await prepareWindowsUpdate(
      const ReleaseInfo('v9.9.9', '', {}),
      zipBytes: bytes,
      installDir: install.path,
      waitPid: fake.pid,
      relaunch: false,
    );
    final r = await Process.run('powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script.path]);
    final log = File('${Platform.environment['TEMP']}\\funilar-atualizacao.log');
    // ignore: avoid_print
    print('saida: ${r.stdout}\nerros: ${r.stderr}\nlog: ${log.existsSync() ? log.readAsStringSync() : '(sem log)'}');
    expect(r.exitCode, 0);
    final exe = File('${install.path}\\funilar.exe');
    expect(exe.lengthSync(), greaterThan(10000), reason: 'exe novo copiado');
    expect(File('${install.path}\\versao.txt').readAsStringSync().trim(), 'v9.9.9');
    expect(File('${install.path}\\data\\icudtl.dat').existsSync(), isTrue);
    expect(File('${install.path}\\data\\flutter_assets\\velho.txt').existsSync(), isTrue,
        reason: 'arquivos que não vêm no zip ficam');
    expect(log.readAsStringSync(), contains('OK'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('baixa e descompacta a última versão publicada', () async {
    final rel = await fetchLatestRelease();
    final a = rel.asset('Funilar-windows-x64.zip');
    expect(a, isNotNull, reason: 'release ${rel.tag} sem o zip do Windows');
    final bytes = await downloadAsset(a!.$1, a.$2, null);
    expect(bytes.length, a.$2);
    final dir = await Directory.systemTemp.createTemp('fn_baixado');
    expect(await extractWindowsZip(bytes, dir), isTrue);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
