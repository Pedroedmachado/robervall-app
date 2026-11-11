// Leitura de notas por foto, no próprio aparelho e sem internet:
//  - Android e iPhone: ML Kit;
//  - Windows: o leitor de texto que já vem no Windows 10/11 (Windows.Media.Ocr);
//  - Linux: Tesseract, se estiver instalado.
import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'modules.dart';
import 'receipt_parser.dart';

/// Onde a leitura por foto existe.
bool get receiptOcrAvailable =>
    Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isLinux;

/// Problema que a pessoa consegue resolver (falta instalar algo).
class OcrProblem implements Exception {
  OcrProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lê a foto e devolve as linhas na ordem em que aparecem na nota.
Future<List<String>> readReceiptLines(String imagePath) async {
  gate.require(Mod.ocr);
  if (Platform.isWindows) return rowsFromPieces(await windowsOcrPieces(imagePath));
  if (Platform.isLinux) return rowsFromPieces(await tesseractPieces(imagePath));
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result =
        await recognizer.processImage(InputImage.fromFilePath(imagePath));
    final pieces = <OcrPiece>[
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrPiece(
            line.text,
            line.boundingBox.left,
            line.boundingBox.top,
            line.boundingBox.right,
            line.boundingBox.bottom,
          ),
    ];
    return rowsFromPieces(pieces);
  } finally {
    await recognizer.close();
  }
}

/// Saída dos leitores do PC: uma linha por trecho, "esq\ttopo\tdir\tbase\ttexto".
List<OcrPiece> parseOcrPieces(String out) {
  final pieces = <OcrPiece>[];
  for (final raw in const LineSplitter().convert(out)) {
    final p = raw.split('\t');
    if (p.length < 5) continue;
    final n = [for (var i = 0; i < 4; i++) double.tryParse(p[i].replaceAll(',', '.'))];
    if (n.any((e) => e == null)) continue;
    final text = p.sublist(4).join(' ').trim();
    if (text.isEmpty) continue;
    pieces.add(OcrPiece(text, n[0]!, n[1]!, n[2]!, n[3]!));
  }
  return pieces;
}

/// Script do Windows: usa o leitor de texto do sistema (o mesmo do
/// "Copiar texto da imagem"), em português quando o idioma está instalado.
const windowsOcrScript = r'''
param([string]$Path)
$ErrorActionPreference = 'Stop'
$step = 'inicio'
try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Add-Type -AssemblyName System.Runtime.WindowsRuntime
  $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
  $null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
  $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
  $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
  $null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
  $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
      $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
      $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
  function Await($op, $type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait(-1) | Out-Null
    $t.Result
  }

  $step = 'idioma'
  $engine = $null
  foreach ($tag in @('pt-BR', 'pt-PT')) {
    try {
      $lang = New-Object Windows.Globalization.Language $tag
      if ([Windows.Media.Ocr.OcrEngine]::IsLanguageSupported($lang)) {
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
        if ($engine -ne $null) { break }
      }
    } catch { }
  }
  if ($engine -eq $null) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
  if ($engine -eq $null) {
    $langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
    if ($langs.Count -gt 0) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($langs[0]) }
  }
  if ($engine -eq $null) { [Console]::Error.WriteLine('SEM_IDIOMA'); exit 3 }

  $step = 'abrir a imagem'
  $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
  $stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
  $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  $step = 'decodificar a imagem'
  $bitmap = $null
  try {
    # respeita a rotação gravada pela câmera do celular e limita o tamanho
    $tr = New-Object Windows.Graphics.Imaging.BitmapTransform
    $max = [double][Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    $w = [double]$decoder.OrientedPixelWidth
    $h = [double]$decoder.OrientedPixelHeight
    $big = [Math]::Max($w, $h)
    if ($big -gt $max) {
      $k = $max / $big
      $tr.ScaledWidth = [uint32][Math]::Floor($decoder.PixelWidth * $k)
      $tr.ScaledHeight = [uint32][Math]::Floor($decoder.PixelHeight * $k)
    }
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync(
        [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
        [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,
        $tr,
        [Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,
        [Windows.Graphics.Imaging.ColorManagementMode]::DoNotColorManage)) ([Windows.Graphics.Imaging.SoftwareBitmap])
  } catch {
    $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  }
  $step = 'ler o texto'
  $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

  $inv = [System.Globalization.CultureInfo]::InvariantCulture
  [Console]::Error.WriteLine('IDIOMA ' + $engine.RecognizerLanguage.LanguageTag)
  foreach ($line in $result.Lines) {
    $l = [double]::MaxValue; $t = [double]::MaxValue; $r = 0.0; $b = 0.0
    foreach ($word in $line.Words) {
      $rc = $word.BoundingRect
      if ($rc.X -lt $l) { $l = $rc.X }
      if ($rc.Y -lt $t) { $t = $rc.Y }
      if (($rc.X + $rc.Width) -gt $r) { $r = $rc.X + $rc.Width }
      if (($rc.Y + $rc.Height) -gt $b) { $b = $rc.Y + $rc.Height }
    }
    $text = ($line.Text -replace "[`t`r`n]", ' ')
    [Console]::Out.WriteLine([string]::Format($inv, "{0:0.#}`t{1:0.#}`t{2:0.#}`t{3:0.#}`t{4}", $l, $t, $r, $b, $text))
  }
  exit 0
} catch {
  $e = $_.Exception
  while ($e.InnerException -ne $null) { $e = $e.InnerException }
  [Console]::Error.WriteLine('ERRO [' + $step + '] ' + $e.Message)
  exit 2
}
''';

/// Caminho completo no formato do Windows (o leitor não aceita "/").
String windowsPath(String path) => File(path).absolute.path.replaceAll('/', r'\');

/// Windows: roda o leitor do sistema pelo PowerShell (não precisa instalar
/// nada no app).
Future<List<OcrPiece>> windowsOcrPieces(String imagePath) async {
  final dir = await Directory.systemTemp.createTemp('funilar_ocr');
  try {
    final script = File('${dir.path}\\ler.ps1');
    // BOM: o PowerShell 5 lê o arquivo como UTF-8
    await script.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(windowsOcrScript)], flush: true);
    final r = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script.path, windowsPath(imagePath)],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 60));
    final err = '${r.stderr}';
    if (r.exitCode == 3 || err.contains('SEM_IDIOMA')) {
      throw OcrProblem(
          'O Windows está sem o leitor de texto (OCR) instalado. Em Configurações › Hora e idioma › Idioma e região, abra as opções do Português (Brasil) e instale "Reconhecimento óptico de caracteres". Depois tente de novo');
    }
    if (r.exitCode != 0) {
      final m = RegExp(r'ERRO (.*)').firstMatch(err);
      throw OcrProblem('o leitor do Windows falhou: ${m?.group(1)?.trim() ?? err.trim()}');
    }
    return parseOcrPieces('${r.stdout}');
  } on ProcessException catch (e) {
    throw OcrProblem('não consegui abrir o PowerShell do Windows (${e.message})');
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Saída "tsv" do Tesseract → um trecho por linha de texto.
List<OcrPiece> parseTesseractTsv(String tsv) {
  final lines = <String, List<List<String>>>{};
  for (final raw in const LineSplitter().convert(tsv)) {
    final c = raw.split('\t');
    if (c.length < 12 || c[0] != '5') continue; // 5 = palavra
    if (c[11].trim().isEmpty) continue;
    lines.putIfAbsent('${c[1]}-${c[2]}-${c[3]}-${c[4]}', () => []).add(c);
  }
  final out = <OcrPiece>[];
  for (final words in lines.values) {
    var l = double.infinity, t = double.infinity, r = 0.0, b = 0.0;
    for (final w in words) {
      final x = double.tryParse(w[6]) ?? 0, y = double.tryParse(w[7]) ?? 0;
      final ww = double.tryParse(w[8]) ?? 0, hh = double.tryParse(w[9]) ?? 0;
      if (x < l) l = x;
      if (y < t) t = y;
      if (x + ww > r) r = x + ww;
      if (y + hh > b) b = y + hh;
    }
    out.add(OcrPiece(words.map((w) => w[11].trim()).join(' '), l, t, r, b));
  }
  return out;
}

/// Linux: Tesseract (português quando o pacote do idioma está instalado).
Future<List<OcrPiece>> tesseractPieces(String imagePath) async {
  ProcessResult r;
  try {
    r = await Process.run('tesseract', [imagePath, 'stdout', '-l', 'por', '--psm', '4', 'tsv'],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    if (r.exitCode != 0) {
      r = await Process.run('tesseract', [imagePath, 'stdout', '--psm', '4', 'tsv'],
          stdoutEncoding: utf8, stderrEncoding: utf8);
    }
  } on ProcessException {
    throw OcrProblem(
        'Para ler fotos no Linux instale o Tesseract (Arch: sudo pacman -S tesseract tesseract-data-por · Ubuntu: sudo apt install tesseract-ocr tesseract-ocr-por)');
  }
  if (r.exitCode != 0) {
    throw OcrProblem('o Tesseract falhou: ${'${r.stderr}'.trim().split('\n').first}');
  }
  return parseTesseractTsv('${r.stdout}');
}
