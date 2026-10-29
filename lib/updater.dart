/// Atualização pelo próprio app: confere a última versão publicada no
/// GitHub e, no Windows, baixa, troca os arquivos e reabre sozinho.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// Versão deste programa (gravada na compilação pelo GitHub Actions).
const appVersion = String.fromEnvironment('FUNILAR_VERSION', defaultValue: 'dev');

const _repo = 'Pedroedmachado/robervall-app';

/// Página das versões (Android/iPhone/Linux abrem por aqui).
const releasesPage = 'https://github.com/$_repo/releases/latest';

class ReleaseInfo {
  const ReleaseInfo(this.tag, this.notes, this.assets);
  final String tag;
  final String notes;
  final Map<String, (String url, int size)> assets;

  (String, int)? asset(String name) => assets[name];
}

/// "v1.0.48" → [1, 0, 48]
List<int> _parts(String v) => RegExp(r'\d+')
    .allMatches(v)
    .map((m) => int.parse(m[0]!))
    .toList();

/// [candidate] é mais nova que [current]? ("dev" nunca é considerada atual).
bool isNewer(String candidate, String current) {
  if (current == 'dev' || current.isEmpty) return true;
  final a = _parts(candidate), b = _parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

Future<ReleaseInfo> fetchLatestRelease({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await c.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'User-Agent': 'Funilar', 'Accept': 'application/vnd.github+json'});
    if (r.statusCode != 200) {
      throw HttpException('GitHub respondeu ${r.statusCode}');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ReleaseInfo(
      '${j['tag_name'] ?? ''}',
      '${j['body'] ?? ''}',
      {
        for (final a in (j['assets'] as List? ?? const []))
          if (a is Map)
            '${a['name']}': ('${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0),
      },
    );
  } finally {
    if (client == null) c.close();
  }
}

/// Nome do arquivo de cada sistema.
String? assetForPlatform() {
  if (Platform.isWindows) return 'Funilar-windows-x64.zip';
  if (Platform.isAndroid) return 'Funilar-android.apk';
  if (Platform.isLinux) return 'Funilar-linux-x64.tar.gz';
  return null;
}

/// Script que espera o app fechar, troca os arquivos e abre de novo.
String windowsSwapScript({
  required int pid,
  required String from,
  required String to,
  required String tag,
}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  return '''
\$ErrorActionPreference = 'SilentlyContinue'
try { Wait-Process -Id $pid -Timeout 60 } catch {}
Start-Sleep -Milliseconds 700
\$ok = \$true
try {
  Copy-Item -Path (Join-Path ${q(from)} '*') -Destination ${q(to)} -Recurse -Force -ErrorAction Stop
  Set-Content -Path (Join-Path ${q(to)} 'versao.txt') -Value ${q(tag)}
} catch { \$ok = \$false }
Remove-Item ${q(from)} -Recurse -Force
if (-not \$ok) {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show('Não consegui trocar os arquivos do Funilar (pasta protegida?). Rode o atualizador pelo PowerShell.', 'Funilar') | Out-Null
}
Start-Process (Join-Path ${q(to)} 'funilar.exe')
''';
}

/// Windows: baixa o .zip, descompacta numa pasta temporária e deixa o
/// script pronto. Depois disso o app só precisa fechar ([launchSwapAndExit]).
Future<File> prepareWindowsUpdate(
  ReleaseInfo rel, {
  void Function(double progress)? onProgress,
}) async {
  final a = rel.asset('Funilar-windows-x64.zip');
  if (a == null) throw StateError('Esta versão não tem o arquivo do Windows.');
  final bytes = await _download(a.$1, a.$2, onProgress);
  final tmp = await Directory.systemTemp.createTemp('funilar_update');
  final files = Directory('${tmp.path}${Platform.pathSeparator}novo');
  await files.create();
  final zip = ZipDecoder().decodeBytes(bytes);
  var hasExe = false;
  for (final f in zip.files) {
    final name = f.name.replaceAll('\\', '/');
    if (name.contains('..')) continue;
    final out = '${files.path}/$name';
    if (f.isFile) {
      await File(out).create(recursive: true);
      await File(out).writeAsBytes(f.content as List<int>, flush: true);
      if (name.toLowerCase() == 'funilar.exe') hasExe = true;
    } else {
      await Directory(out).create(recursive: true);
    }
  }
  if (!hasExe) throw StateError('O arquivo baixado não tem o funilar.exe.');
  final installDir = File(Platform.resolvedExecutable).parent.path;
  final script = File('${tmp.path}${Platform.pathSeparator}trocar.ps1');
  // BOM: o PowerShell do Windows lê acentos certo
  await script.writeAsBytes([
    0xEF, 0xBB, 0xBF,
    ...utf8.encode(windowsSwapScript(
        pid: pid, from: files.path, to: installDir, tag: rel.tag)),
  ]);
  return script;
}

/// Roda o script em segundo plano (ele espera este processo fechar).
Future<void> launchSwapScript(File script) async {
  await Process.start(
    'powershell.exe',
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
    mode: ProcessStartMode.detached,
  );
}

Future<List<int>> _download(
    String url, int size, void Function(double)? onProgress) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'Funilar';
    final res = await client.send(req);
    if (res.statusCode != 200) {
      throw HttpException('Download falhou (${res.statusCode})');
    }
    final total = res.contentLength ?? size;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      out.add(chunk);
      if (total > 0) onProgress?.call(out.length / total);
    }
    return out.takeBytes();
  } finally {
    client.close();
  }
}
