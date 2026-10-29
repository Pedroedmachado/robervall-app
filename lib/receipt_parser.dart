// Interpreta o texto lido (OCR) de notas, cupons e recibos de compra.
import 'models.dart';

/// Pedaço de texto com posição na foto (como o OCR devolve).
class OcrPiece {
  final String text;
  final double left, top, right, bottom;
  const OcrPiece(this.text, this.left, this.top, this.right, this.bottom);
  double get cy => (top + bottom) / 2;
  double get h => (bottom - top).abs();
}

/// Junta os pedaços que estão na mesma altura em linhas, da esquerda para a
/// direita (o OCR costuma separar colunas de quantidade/preço/total).
List<String> rowsFromPieces(List<OcrPiece> pieces) {
  final sorted = [...pieces]..sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <List<OcrPiece>>[];
  for (final p in sorted) {
    if (rows.isNotEmpty) {
      final last = rows.last;
      final ref = last.first;
      final tol = (ref.h < p.h ? ref.h : p.h) * 0.6;
      if ((p.cy - ref.cy).abs() <= tol) {
        last.add(p);
        continue;
      }
    }
    rows.add([p]);
  }
  return [
    for (final r in rows)
      (r..sort((a, b) => a.left.compareTo(b.left)))
          .map((p) => p.text.trim())
          .join('   ')
  ];
}

class ReceiptItem {
  final String description;
  final double qty;
  final String unit;
  final double unitPrice;
  final double total;
  const ReceiptItem(
      this.description, this.qty, this.unit, this.unitPrice, this.total);
}

class ReceiptData {
  final String supplier;
  final DateTime? date;
  final double total;
  final List<ReceiptItem> items;
  final ExpenseCategory category;
  final String rawText;

  const ReceiptData({
    required this.supplier,
    required this.date,
    required this.total,
    required this.items,
    required this.category,
    required this.rawText,
  });

  double get itemsSum => items.fold(0.0, (a, i) => a + i.total);

  /// Resumo dos itens para a observação do lançamento.
  String get itemsText => items
      .map((i) =>
          '${i.description} — ${_fmtQty(i.qty)} ${i.unit.toLowerCase()} × ${_money(i.unitPrice)} = ${_money(i.total)}'
              .replaceAll('  ', ' '))
      .join('\n');

  FinanceEntry toEntry() => FinanceEntry(
        isIncome: false,
        date: date ?? DateTime.now(),
        description: supplier.isEmpty ? 'Compra' : supplier,
        contact: supplier,
        category: category,
        amount: total,
        notes: itemsText,
      );
}

final _moneyRe = RegExp(r'(\d{1,3}(?:[.\s]\d{3})+|\d+)\s?[,.]\s?(\d{2})(?!\d)');
final _dateRe = RegExp(r'(\d{2})\s?[/.-]\s?(\d{2})\s?[/.-]\s?(\d{2,4})');

/// Corrige confusões comuns do OCR em trechos numéricos (O→0, I/l→1, S→5).
String _fixDigits(String s) {
  var prev = '';
  while (prev != s) {
    prev = s;
    s = _fixOnce(s);
  }
  return s;
}

String _fixOnce(String s) => s.replaceAllMapped(
      RegExp(r'(?<=[\d,.])[OoIlSB]|[OoIlSB](?=[\d,.]\d)'),
      (m) => const {
            'O': '0',
            'o': '0',
            'I': '1',
            'l': '1',
            'S': '5',
            'B': '8',
          }[m[0]!] ??
          m[0]!,
    );

List<double> _moneys(String line) => _moneyRe
    .allMatches(_fixDigits(line))
    .map((m) =>
        double.parse('${m[1]!.replaceAll(RegExp(r'[.\s]'), '')}.${m[2]}'))
    .toList();

String _norm(String s) {
  const from = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç';
  const to = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toUpperCase();
}

String _title(String s) => s
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w.length <= 2 && w != 'sp'
        ? w
        : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _fmtQty(double q) {
  var s = q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s.replaceAll('.', ',');
}

String _money(double v) {
  final cents = (v * 100).round();
  final s = (cents ~/ 100).toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return 'R\$ $b,${(cents % 100).toString().padLeft(2, '0')}';
}

const _ignoreTotal = [
  'DEBITO', 'SUBTOTAL', 'SUB TOTAL', 'ITENS', 'QTDE', 'QTD', 'TROCO',
  'DESCONTO', 'TRIBUTO', 'IMPOSTO', 'LEI ', 'APROX', 'CREDITO', 'SALDO',
];
const _strongTotal = [
  'TOTAL A PAGAR', 'VALOR A PAGAR', 'VALOR TOTAL', 'TOTAL R', 'TOTAL:',
  'TOTAL :', 'TOTAL GERAL', 'TOTAL DA NOTA', 'VL TOTAL', 'VLR TOTAL',
];
const _headerNoise = [
  'CNPJ', 'CPF', 'CUPOM', 'DOCUMENTO', 'NOTA', 'FONE', 'TEL', 'RUA', 'AV ',
  'AV.', 'RESERVA', 'PEDIDO', 'IE ', 'INSC', 'DATA', 'EXTRATO', 'DANFE',
  'NFC-E', 'SAT', 'ORCAMENTO',
];
const _materialWords = [
  'TINTA', 'VERNIZ', 'PRIMER', 'MASSA', 'LIXA', 'THINNER', 'SOLVENTE',
  'CATALIS', 'ACELERADOR', 'FITA', 'ESTOPA', 'DILUENTE', 'BASE ', 'POLIDOR',
  'COMPOSTO', 'CERA', 'FUNDO', 'ADESIVO', 'COLA', 'MASCARAMENTO', 'PAPEL',
  'LUVA', 'MASCARA', 'DISCO', 'ESMALTE', 'PU ', 'ANTICORROS',
];
const _partWords = [
  'PARA-CHOQUE', 'PARACHOQUE', 'PARA CHOQUE', 'FAROL', 'LANTERNA', 'PORTA',
  'CAPO', 'PARALAMA', 'PARA-LAMA', 'RETROVISOR', 'GRADE', 'RADIADOR',
  'AMORTECEDOR', 'PASTILHA', 'FILTRO', 'OLEO', 'VIDRO', 'MAQUINA', 'MACANETA',
  'BORRACHA', 'SUPORTE', 'AUTOPECAS', 'AUTO PECAS', 'PECAS',
];

/// Lê o texto da nota (uma linha por linha impressa).
ReceiptData parseReceipt(List<String> rawLines) {
  final lines = [
    for (final l in rawLines)
      if (l.trim().isNotEmpty) l.trim()
  ];
  final up = [for (final l in lines) _norm(l)];

  // data: a primeira data válida
  DateTime? date;
  for (final l in up) {
    final m = _dateRe.firstMatch(_fixDigits(l));
    if (m == null) continue;
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final mo = int.parse(m[2]!), d = int.parse(m[1]!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && y >= 2000 && y <= 2100) {
      date = DateTime(y, mo, d);
      break;
    }
  }

  // itens: descrição seguida de "qtd unidade preço total" (ou tudo na mesma linha)
  final items = <ReceiptItem>[];
  final qtyLine = RegExp(
      r'^\s*(\d+(?:[,.]\d+)?)\s*([A-Z]{1,6})?\.?\s+.*?(\d[\d.\s]*[,.]\d{2})\s+.*?(\d[\d.\s]*[,.]\d{2})\s*$');
  final sameLine = RegExp(
      r'^(.*?[A-Z].*?)\s(\d+(?:[,.]\d+)?)\s*([A-Z]{1,6})?\.?\s+[\d.\s]*[,.]\d{2}\s+[\d.\s]*[,.]\d{2}\s*$');
  for (var i = 0; i < up.length; i++) {
    final l = _fixDigits(up[i]);
    if (l.contains('TOTAL') || l.contains('QTDE')) continue;
    final vals = _moneys(l);
    if (vals.length < 2) continue;
    final unit = vals[vals.length - 2], total = vals.last;
    final m = qtyLine.firstMatch(l);
    if (m != null) {
      // linha só com números: a descrição está na linha de cima
      final qty = double.tryParse(m[1]!.replaceAll(',', '.')) ?? 1;
      if ((qty * unit - total).abs() > 0.05 * (total.abs() + 1)) continue;
      var desc = '';
      if (i > 0 && _moneys(up[i - 1]).isEmpty && !up[i - 1].contains('---')) {
        desc = lines[i - 1];
      }
      items.add(ReceiptItem(
          _cleanDesc(desc), qty, (m[2] ?? '').trim(), unit, total));
      continue;
    }
    // tudo na mesma linha: "DESCRICAO  1 UN  300,00  300,00"
    final same = sameLine.firstMatch(l);
    if (same == null) continue;
    final qty = double.tryParse(same[2]!.replaceAll(',', '.')) ?? 1;
    if ((qty * unit - total).abs() > 0.05 * (total.abs() + 1)) continue;
    final desc = lines[i].substring(0, same.start(2).clamp(0, lines[i].length));
    items.add(ReceiptItem(
        _cleanDesc(desc), qty, (same[3] ?? '').trim(), unit, total));
  }
  final sum = items.fold(0.0, (a, i) => a + i.total);

  // total: linha com "TOTAL" que não seja débito, subtotal, impostos...
  double? total;
  double bestScore = -1;
  for (final l in up) {
    if (!l.contains('TOTAL') && !l.contains('A PAGAR')) continue;
    if (_ignoreTotal.any(l.contains)) continue;
    final vals = _moneys(l);
    if (vals.isEmpty) continue;
    final v = vals.last;
    var score = 1.0;
    if (_strongTotal.any(l.contains)) score += 1;
    if (sum > 0 && (v - sum).abs() < 0.02) score += 3;
    if (score > bestScore) {
      bestScore = score;
      total = v;
    }
  }
  total ??= sum > 0 ? sum : null;
  // último recurso: o maior valor fora de linhas de débito/saldo
  if (total == null) {
    final all = [
      for (final l in up)
        if (!_ignoreTotal.any(l.contains)) ..._moneys(l)
    ];
    if (all.isNotEmpty) total = all.reduce((a, b) => a > b ? a : b);
  }

  // loja: primeira linha de texto do cabeçalho
  var supplier = '';
  for (var i = 0; i < up.length && i < 6; i++) {
    final l = up[i];
    final letters = RegExp(r'[A-Z]').allMatches(l).length;
    if (letters < 3 || l.contains('---')) continue;
    if (_headerNoise.any(l.startsWith) || _headerNoise.any((n) => l.contains(' $n'))) {
      continue;
    }
    if (RegExp(r'\d{2}[/.]\d{2}[/.]\d{2}').hasMatch(l)) continue;
    supplier = _title(lines[i].replaceAll(RegExp(r'[^\wÀ-ú&.\- ]'), ' ').trim());
    break;
  }

  // categoria pelo conteúdo
  final everything = up.join(' ');
  final materials = _materialWords.where(everything.contains).length;
  final parts = _partWords.where(everything.contains).length;
  final category = materials == 0 && parts == 0
      ? ExpenseCategory.outros
      : (parts > materials
          ? ExpenseCategory.fornecedor
          : ExpenseCategory.materiais);

  return ReceiptData(
    supplier: supplier,
    date: date,
    total: total ?? 0,
    items: items,
    category: category,
    rawText: lines.join('\n'),
  );
}

String _cleanDesc(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return 'Item';
  return _title(t)
      .replaceAllMapped(RegExp(r'\b(Hs|Lt|Ml|Kg|Pu|Sky)\b'),
          (m) => m[0]!.toUpperCase())
      .replaceAll(' C/cat', ' c/ cat');
}
