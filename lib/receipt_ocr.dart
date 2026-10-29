// Leitura de notas pela câmera (ML Kit, no próprio aparelho, sem internet).
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'receipt_parser.dart';

/// O leitor funciona no Android e no iPhone.
bool get receiptOcrAvailable => Platform.isAndroid || Platform.isIOS;

/// Lê a foto e devolve as linhas na ordem em que aparecem na nota.
Future<List<String>> readReceiptLines(String imagePath) async {
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
