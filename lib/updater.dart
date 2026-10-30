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
/// Usa robocopy (tenta de novo se algum arquivo ainda estiver em uso) e
/// grava um log em %TEMP%\funilar-atualizacao.log.
String windowsSwapScript({
  required int pid,
  required String from,
  required String to,
  required String tag,
  bool relaunch = true,
}) {
  String q(String s) => "'${s.replaceAll("'", "''")}'";
  String plain(String s) => s.replaceAll("'", '').replaceAll('"', '');
  final reopen = relaunch
      ? "Start-Process (Join-Path ${q(to)} 'funilar.exe')"
      : "Log 'sem reabrir (teste)'";
  return '''
\$log = Join-Path \$env:TEMP 'funilar-atualizacao.log'
function Log(\$m) { Add-Content -Path \$log -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), \$m) }
Log "Atualizando para ${plain(tag)} de=${plain(from)} para=${plain(to)}"
try { Wait-Process -Id $pid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 800
\$ok = \$false
for (\$i = 1; \$i -le 5 -and -not \$ok; \$i++) {
  & robocopy ${q(from)} ${q(to)} /E /R:3 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  \$code = \$LASTEXITCODE
  Log "robocopy tentativa \$(\$i): codigo \$(\$code)"
  if (\$code -lt 8) { \$ok = \$true } else { Start-Sleep -Seconds 2 }
}
if (\$ok) {
  Set-Content -Path (Join-Path ${q(to)} 'versao.txt') -Value ${q(tag)}
  Remove-Item ${q(from)} -Recurse -Force -ErrorAction SilentlyContinue
  Log 'OK'
} else {
  Log 'FALHOU'
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("Não consegui trocar os arquivos do Funilar. Veja o log em \$log ou rode o atualizador pelo PowerShell.", 'Funilar') | Out-Null
}
$reopen
''';
}

/// Descompacta o .zip do Windows. Devolve true se tem o funilar.exe.
Future<bool> extractWindowsZip(List<int> bytes, Directory into) async {
  final zip = ZipDecoder().decodeBytes(bytes);
  var hasExe = false;
  for (final f in zip.files) {
    final name = f.name.replaceAll('\\', '/');
    if (name.contains('..') || name.startsWith('/')) continue;
    final out = '${into.path}/$name';
    if (f.isFile) {
      await File(out).create(recursive: true);
      await File(out).writeAsBytes(f.content as List<int>, flush: true);
      if (name.toLowerCase() == 'funilar.exe') hasExe = true;
    } else {
      await Directory(out).create(recursive: true);
    }
  }
  return hasExe;
}

/// Windows: baixa o .zip, descompacta numa pasta temporária e deixa o
/// script pronto. Depois disso o app só precisa fechar.
Future<File> prepareWindowsUpdate(
  ReleaseInfo rel, {
  void Function(double progress)? onProgress,
  List<int>? zipBytes,
  String? installDir,
  int? waitPid,
  bool relaunch = true,
}) async {
  List<int> bytes;
  if (zipBytes != null) {
    bytes = zipBytes;
  } else {
    final a = rel.asset('Funilar-windows-x64.zip');
    if (a == null) throw StateError('Esta versão não tem o arquivo do Windows.');
    bytes = await downloadAsset(a.$1, a.$2, onProgress);
  }
  final tmp = await Directory.systemTemp.createTemp('funilar_update');
  final files = Directory('${tmp.path}${Platform.pathSeparator}novo');
  await files.create();
  if (!await extractWindowsZip(bytes, files)) {
    throw StateError('O arquivo baixado não tem o funilar.exe.');
  }
  final to = installDir ?? File(Platform.resolvedExecutable).parent.path;
  final script = File('${tmp.path}${Platform.pathSeparator}trocar.ps1');
  // BOM: o PowerShell do Windows lê acentos certo
  await script.writeAsBytes([
    0xEF, 0xBB, 0xBF,
    ...utf8.encode(windowsSwapScript(
        pid: waitPid ?? pid,
        from: files.path,
        to: to,
        tag: rel.tag,
        relaunch: relaunch)),
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

Future<List<int>> downloadAsset(
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
