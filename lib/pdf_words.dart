import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'quote_import.dart';

/// Tira as palavras (com posição) de um PDF com texto. PDF escaneado (só
/// imagem) volta vazio.
List<PdfWord> extractPdfWords(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final lines = PdfTextExtractor(doc).extractTextLines();
    final out = <PdfWord>[];
    for (final l in lines) {
      for (final w in l.wordCollection) {
        final t = w.text.trim();
        if (t.isEmpty) continue;
        final b = w.bounds;
        out.add(PdfWord(l.pageIndex, t, b.left, b.top, b.right));
      }
    }
    return out;
  } finally {
    doc.dispose();
  }
}

/// Atalho: PDF → orçamento importado.
ImportedQuote importQuotePdf(Uint8List bytes) =>
    parseInsurerQuote(extractPdfWords(bytes));
