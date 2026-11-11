import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/receipt_ocr.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/stock_entry.dart';

void main() {
  test('saída do leitor do Windows vira linhas da nota', () {
    const out = '50.0\t50.5\t420\t80\tTINTAS EXEMPLO LTDA\r\n'
        '50\t470\t760\t500\tVERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY\r\n'
        '120\t516\t330\t546\t3,00 QUART\r\n'
        '430\t517\t520\t547\t89,00\r\n'
        '610\t516\t720\t546\t267,00\r\n'
        'linha quebrada\r\n'
        '300\t960\t420\t990\tTOTAL :\r\n'
        '600\t961\t720\t991\t267,00\r\n';
    final pieces = parseOcrPieces(out);
    expect(pieces.length, 7);
    final lines = rowsFromPieces(pieces);
    expect(lines[2], '3,00 QUART   89,00   267,00');
    final d = parseReceipt(lines);
    expect(d.items.single.description.toUpperCase(), startsWith('VERNIZ'));
    expect(d.items.single.qty, 3);
    expect(d.total, 267);
  });

  test('linhas como o leitor do Windows devolve (centavos separados, letras soltas)', () {
    final d = parseReceipt(const [
      'TINTAS EXEMPLO LTDA',
      'RESERVA 0123456',
      '30/10/2026-13:50 VEND:   00010 -FULANO',
      'QTDE UNID   PRC UNIT   TOTAL',
      'VERNIZ A. SOLIDOS HS-2X1 13000 C/CAT.SKY',
      '3,00 QUART   89,00   267 , oo',
      'THINNER PIJ /POLIES.TH700 900ML SKY',
      '2,00 L ITRO   41,00   82,00',
      'L IXA DAGUA 1200 NORTON-AMARELA',
      '5,00 FL   6,95   34,75',
      'TOTAL   383,75',
    ]);
    expect(d.items.length, 3);
    expect(d.items.first.total, 267);
    expect(d.items[1].qty, 2);
    expect(d.total, 383.75);
    expect(d.date, DateTime(2026, 10, 30));
  });

  test('saída tsv do Tesseract vira trechos por linha', () {
    const tsv = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
        '4\t1\t1\t1\t1\t0\t51\t56\t341\t22\t-1\t\n'
        '5\t1\t1\t1\t1\t1\t51\t56\t105\t22\t90.7\tTINTAS\n'
        '5\t1\t1\t1\t1\t2\t179\t56\t122\t22\t92.6\tEXEMPLO\n'
        '5\t1\t1\t2\t1\t1\t51\t102\t34\t22\t96.0\tAV\n';
    final p = parseTesseractTsv(tsv);
    expect(p.length, 2);
    expect(p.first.text, 'TINTAS EXEMPLO');
    expect(p.first.left, 51);
    expect(p.first.right, 301);
  });

  // Leitor de verdade do sistema: Windows (Windows.Media.Ocr) e Linux
  // (Tesseract, quando instalado), numa nota de exemplo.
  test('PC: lê a foto da nota de exemplo e monta a entrada no estoque', () async {
    final image = File('test/fixtures/nota_exemplo.png').absolute.path;
    List<OcrPiece> pieces;
    if (Platform.isWindows) {
      pieces = await windowsOcrPieces(image);
    } else if (Platform.isLinux) {
      try {
        await Process.run('tesseract', ['--version']);
      } on ProcessException {
        markTestSkipped('Tesseract não instalado');
        return;
      }
      pieces = await tesseractPieces(image);
    } else {
      markTestSkipped('só Windows e Linux');
      return;
    }
    final lines = rowsFromPieces(pieces);
    // ignore: avoid_print
    print('--- linhas lidas (${Platform.operatingSystem})\n${lines.join('\n')}\n---');
    final d = parseReceipt(lines);
    expect(d.supplier.toUpperCase(), contains('TINTAS EXEMPLO'));
    expect(d.total, closeTo(555.05, 0.001));
    expect(d.items.length, 5, reason: d.items.map((e) => e.description).join(' | '));
    expect(d.itemsSum, closeTo(555.05, 0.001));
    final entry = planStockEntry(d, []);
    expect(entry.length, 5);
    expect(entry.every((l) => l.kind == StockKind.material), isTrue);
    expect(entry.first.packSize, 900); // QUART = lata de 900 ml
  }, timeout: const Timeout(Duration(minutes: 3)));
}
