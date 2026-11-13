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

  /// Código do produto no fornecedor (NF-e: cProd).
  final String code;
  const ReceiptItem(
      this.description, this.qty, this.unit, this.unitPrice, this.total,
      {this.code = ''});
}

class ReceiptData {
  final String supplier;
  final DateTime? date;
  final double total;
  final List<ReceiptItem> items;
  final ExpenseCategory category;
  final String rawText;
  final String docNumber; // ex.: "Reserva 0819365"
  final String payment; // ex.: "À vista"

  const ReceiptData({
    required this.supplier,
    required this.date,
    required this.total,
    required this.items,
    required this.category,
    required this.rawText,
    this.docNumber = '',
    this.payment = '',
  });

  /// Descrição curta: loja e os primeiros itens.
  String get shortDescription {
    final names = items
        .take(3)
        .map((i) => i.description.split(' ').first)
        .where((n) => n.isNotEmpty)
        .toList();
    final base = supplier.isEmpty ? 'Compra' : supplier;
    if (names.isEmpty) return base;
    return '$base · ${names.join(', ')}${items.length > 3 ? '…' : ''}';
  }

  /// Resumo completo da nota para guardar no lançamento.
  String get summary {
    final head = [
      if (docNumber.isNotEmpty) docNumber,
      if (date != null)
        '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}',
      if (payment.isNotEmpty) payment,
    ].join(' · ');
    return [
      if (head.isNotEmpty) 'Nota: $head',
      for (final i in items)
        '• ${i.description} — ${_fmtQty(i.qty)}${i.unit.isEmpty ? '' : ' ${i.unit.toLowerCase()}'} × ${_money(i.unitPrice)} = ${_money(i.total)}',
      if (total > 0) 'Total: ${_money(total)}',
    ].join('\n');
  }

  double get itemsSum => items.fold(0.0, (a, i) => a + i.total);

  /// Resumo dos itens para a observação do lançamento.
  String get itemsText => items
      .map((i) =>
          '${i.description} — ${_fmtQty(i.qty)} ${i.unit.toLowerCase()} × ${_money(i.unitPrice)} = ${_money(i.total)}'
              .replaceAll('  ', ' '))
      .join('\n');

  FinanceEntry toEntry() => applyTo(FinanceEntry());

  /// Preenche um lançamento com o que foi lido (sem apagar o que não foi achado).
  FinanceEntry applyTo(FinanceEntry e) {
    e.isIncome = false;
    if (date != null) e.date = date!;
    e.description = shortDescription;
    if (supplier.isNotEmpty) e.contact = supplier;
    if (items.isNotEmpty || supplier.isNotEmpty) e.category = category;
    if (total > 0) e.amount = total;
    if (docNumber.isNotEmpty) e.invoiceNumber = docNumber;
    if (payment.isNotEmpty) e.paymentMethod = payment;
    e.notes = summary;
    return e;
  }
}

final _moneyRe = RegExp(r'(\d{1,3}(?:[.\s]\d{3})+|\d+)\s?[,.]\s?(\d{2})(?!\d)');
final _dateRe = RegExp(r'(\d{2})\s?[/.-]\s?(\d{2})\s?[/.-]\s?(\d{2,4})');

/// O leitor do PC às vezes separa os centavos: "267 , oo" → "267,00".
String _tidyDecimals(String s) => s.replaceAllMapped(
    RegExp(r'(\d) ?, ?([0-9oO]{2})(?![0-9A-Za-z])'),
    (m) => '${m[1]},${m[2]!.replaceAll(RegExp('[oO]'), '0')}');

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
      if (l.trim().isNotEmpty) _tidyDecimals(l.trim())
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
  final itemLines = <int>{};
  final items = extractReceiptItems(lines, up, usedLines: itemLines);
  final sum = items.fold(0.0, (a, i) => a + i.total);

  // total: linha com "TOTAL" que não seja débito, subtotal, impostos...
  double? total;
  double bestScore = -1;
  for (final (li, l) in up.indexed) {
    if (itemLines.contains(li)) continue; // produto com "TOTAL" no nome
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

  // nº da nota / reserva / pedido
  var doc = '';
  final docRe = RegExp(
      r'\b(RESERVA|PEDIDO|CUPOM|NFC-?E|NF-?E|NOTA FISCAL|NOTA|FATURA|VENDA|ORCAMENTO|DOCUMENTO)\b(?:\s+A\s+(?:PRAZO|VISTA))?\s*(?:N[O°º]?\.?|NUMERO)?\s*[:#-]?\s*(\d{3,})');
  for (final l in up) {
    if (l.contains('SEM VALOR')) continue;
    final m = docRe.firstMatch(_fixDigits(l));
    if (m != null) {
      doc = '${_title(m[1]!)} ${m[2]}';
      break;
    }
  }

  // forma de pagamento
  var payment = '';
  for (final l in up) {
    final t = l.trim();
    if (t.contains('TOTAL')) continue;
    if (RegExp(r'^A ?VISTA\b').hasMatch(t) || t.contains('PAGAMENTO A VISTA')) {
      payment = 'À vista';
    } else if (t.contains('PIX')) {
      payment = 'Pix';
    } else if (t.contains('CARTAO') && t.contains('CRED')) {
      payment = 'Cartão de crédito';
    } else if (t.contains('CARTAO') && t.contains('DEB')) {
      payment = 'Cartão de débito';
    } else if (t.contains('DINHEIRO')) {
      payment = 'Dinheiro';
    } else if (t.contains('BOLETO')) {
      payment = 'Boleto';
    } else if (t.contains('A PRAZO') || t.contains('PARCEL')) {
      payment = 'A prazo';
    }
    if (payment.isNotEmpty) break;
  }

  return ReceiptData(
    supplier: supplier,
    date: date,
    total: total ?? 0,
    items: items,
    category: category,
    rawText: lines.join('\n'),
    docNumber: doc,
    payment: payment,
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


// ---------------------------------------------------------------- itens
//
// Leitura dos itens que não depende do layout da nota: cada linha é
// separada em palavras; o "rabo" numérico da linha (quantidade, unidade,
// preço, total — em qualquer ordem comum) é interpretado conferindo a conta
// (qtd × preço = total). A descrição é o que vem antes; se a linha só tem
// números, a descrição é a linha de cima. Serve para:
//   "DESCRICAO" / "4,00 QUART 89,00 356,00"      (nota de balcão)
//   "FAROL ESQ 1 UN 300,00 300,00"                (tudo na mesma linha)
//   "001 7891234567890 LEITE 1L 2 UN X 4,99 9,98" (cupom fiscal / NFC-e)
//   "PARAFUSO M8 2 x 1,50 = 3,00"                 (com "x" e "=")
//   "LIXA 1200 5 FL 6,95 1,00 33,75"              (com desconto no meio)
//   "ESTOPA 12,00"                                 (só o valor: qtd 1)

const _unitWords = {
  'UN', 'UND', 'UNID', 'UNI', 'U', 'PC', 'PCS', 'PCA', 'PÇ', 'PECA', 'CX', 'CJ',
  'JG', 'KIT', 'KG', 'G', 'GR', 'GRS', 'L', 'LT', 'LTS', 'LITRO', 'LITROS',
  'ML', 'M', 'MT', 'MTS', 'M2', 'M3', 'FL', 'FLS', 'FOLHA', 'RL', 'ROLO',
  'PR', 'PAR', 'GL', 'GALAO', 'QT', 'QUART', 'QUARTO', 'LATA', 'TB', 'TUBO',
  'FR', 'FRASCO', 'SC', 'SACO', 'BD', 'BALDE', 'DZ', 'POTE', 'EMB', 'BL',
  'BLOCO', 'CT', 'DISCO',
};
const _fillWords = {'X', '*', '=', 'R\$', 'RS', 'QTD', 'QTDE', 'QT.', 'VL', 'VLR', 'UNIT', 'UNIT.', 'VL.'};
/// Linha que começa como total/pagamento (não é produto mesmo com 3 números).
final _totalStart = RegExp(
    r'^\W*(?:(?:VALOR|VL|VLR|SUB|QTD|QTDE|QT)\.?\s+)?(?:SUB\s?)?(?:TOTAL|TROCO|DESCONTO|PAGO|PAGAMENTO|DINHEIRO|CARTAO|CREDITO|DEBITO|PIX|SALDO|FRETE|JUROS|ICMS|IPI|TRIBUTOS?|IMPOSTOS?)\b');

final _notItem = RegExp(
    r'\b(TOTAL|SUBTOTAL|TROCO|DESCONTO|ACRESC\w*|PAGO|PAGAMENTO|DINHEIRO|CARTAO|CREDITO|DEBITO|PIX|SALDO|TRIBUTOS?|IMPOSTOS?|LEI|APROX\w*|CNPJ|CPF|FONE|TEL|PARCELAS?|VENCIMENTO|JUROS|FRETE|ICMS|IPI|CHAVE|PROTOCOLO|CONSUMIDOR)\b|VALOR A PAGAR|QTDE UNID|PRC UNIT|VL UNIT|VALOR UNIT|BASE DE CALC');

/// Número de nota: "4,00", "1.234,56", "2,000", "47.50", "3". null se não for.
double? _num(String t) {
  var s = t.replaceAll(RegExp(r'^R\$'), '').replaceAll(RegExp(r'[=:]$'), '');
  if (s.startsWith('-')) return null;
  if (!RegExp(r'^\d[\d.,]*$').hasMatch(s)) return null;
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)?$').hasMatch(s)) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d+,\d+$').hasMatch(s)) {
    s = s.replaceAll(',', '.');
  } else if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
    return null;
  }
  return double.tryParse(s);
}

/// Tem cara de dinheiro (com centavos): "12,90", "1.234,50", "47.50".
bool _isMoney(String t) {
  final s = t.replaceAll(RegExp(r'^R\$'), '');
  return RegExp(r'^\d{1,3}(\.\d{3})*,\d{2,4}$|^\d+,\d{2,4}$|^\d+\.\d{2}$').hasMatch(s) &&
      _num(s) != null;
}

bool _isUnit(String t) {
  final s = t.replaceAll('.', '');
  if (_unitWords.contains(s)) return true;
  // embalagem: "750GR", "900ML", "1KG", "18L"
  return RegExp(r'^\d+(?:[.,]\d+)?(ML|L|LT|LTS|KG|G|GR|GRS|M|MT|MTS)$').hasMatch(s);
}

bool _close(double a, double b) => (a - b).abs() <= 0.02 + 0.03 * b.abs();

/// Ajeita a linha para virar palavras: "2UNX1,50" → "2 UN X 1,50".
List<String> _tokens(String upLine) {
  var l = upLine
      .replaceAll(RegExp(r'R\$\s*'), 'R\$ ')
      .replaceAllMapped(RegExp(r'(\d)\s*[X\*]\s*(\d+[,.]\d)'), (m) => '${m[1]} X ${m[2]}')
      .replaceAllMapped(RegExp(r'(\d)(UN|UND|PC|PCS|CX|KIT|FL)\b'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'\b(UN|UND|PC|PCS|CX|KIT|FL)(X)\b'), (m) => '${m[1]} ${m[2]}')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (l.isEmpty) return const [];
  // OCR do PC às vezes separa uma letra: "L ITRO" → "LITRO"
  final out = <String>[];
  final raw = l.split(' ');
  for (var i = 0; i < raw.length; i++) {
    if (i + 1 < raw.length &&
        RegExp(r'^[A-Z]$').hasMatch(raw[i]) &&
        RegExp(r'^[A-Z]+$').hasMatch(raw[i + 1]) &&
        _unitWords.contains(raw[i] + raw[i + 1])) {
      out.add(raw[i] + raw[i + 1]);
      i++;
      continue;
    }
    out.add(raw[i]);
  }
  return out;
}

class _Tail {
  _Tail(this.start, this.qty, this.unitPrice, this.total, this.unit, this.strong,
      {this.exact = false});
  final int start; // primeira palavra que é da parte numérica
  final double qty, unitPrice, total;
  final String unit;
  final bool strong; // a conta qtd × preço = total confere
  final bool exact; // os três números estão na linha (qtd, preço e total)
}

/// Interpreta o fim da linha. null = a linha não é item.
_Tail? _readTail(List<String> tk) {
  if (tk.isEmpty || !_isMoney(tk.last)) return null;
  // anda do fim para o começo enquanto for número/unidade/x/=/R$
  final idx = <int>[]; // índices das palavras numéricas
  var i = tk.length - 1;
  for (; i >= 0; i--) {
    final t = tk[i];
    if (_num(t) != null) {
      idx.insert(0, i);
      continue;
    }
    if (_isUnit(t) || _fillWords.contains(t)) continue;
    break;
  }
  if (idx.isEmpty) return null;
  final v = [for (final k in idx) _num(tk[k])!];
  String unitAfter(int k) {
    for (var j = k + 1; j < tk.length && j <= k + 2; j++) {
      if (_isUnit(tk[j])) return tk[j].replaceAll(RegExp(r'\.$'), '');
    }
    return '';
  }

  bool qtyOk(double q) => q > 0 && q <= 9999;
  final n = v.length;
  // qtd × preço = preço × qtd: qual dos dois é a quantidade? O que tem
  // unidade depois, não tem cara de dinheiro ou é número inteiro.
  int qtyScore(int j) =>
      (unitAfter(idx[j]).isNotEmpty ? 2 : 0) +
      (_isMoney(tk[idx[j]]) ? 0 : 1) +
      (v[j] == v[j].roundToDouble() ? 1 : 0);
  List<(int, int)> orders(int k) => qtyScore(k - 1) > qtyScore(k - 2)
      ? [(k - 1, k - 2), (k - 2, k - 1)]
      : [(k - 2, k - 1), (k - 1, k - 2)];
  bool near(double a, double b) => (a - b).abs() <= 0.05;
  // procura, da direita para a esquerda, três números em que a conta fecha:
  // (qtd, preço, total) ou (preço, qtd, total). Colunas de imposto depois do
  // total (DANFE) ficam de fora.
  for (var k = n - 1; k >= 2; k--) {
    final t = v[k];
    if (t <= 0 || !_isMoney(tk[idx[k]])) continue;
    for (final (qi, pi) in orders(k)) {
      final q = v[qi], p = v[pi];
      if (qtyOk(q) && p > 0 && _close(q * p, t)) {
        return _Tail(idx[k - 2], q, p, t, unitAfter(idx[qi]), true, exact: true);
      }
    }
    // com desconto no meio: (qtd, preço, desconto, total)
    if (k >= 3) {
      final q = v[k - 3], p = v[k - 2], d = v[k - 1];
      final gross = q * p;
      if (qtyOk(q) && p > 0 && t <= gross + 0.02 && t >= gross * 0.5) {
        final asValue = d > 0 && near(gross - d, t);
        final asPct = d > 0 && d < 100 && near(gross * (1 - d / 100), t);
        if ((asValue || asPct) && _hasLetters(tk.take(idx[k - 3]).join(' '))) {
          return _Tail(idx[k - 3], q, t / q, t, unitAfter(idx[k - 3]), true, exact: true);
        }
      }
    }
  }
  // pula zeros no fim (colunas de imposto vazias)
  var m = n;
  while (m > 1 && v[m - 1] == 0) {
    m--;
  }
  if (m >= 3) {
    for (var k = m - 1; k >= 2; k--) {
      final t = v[k];
      for (final (qi, pi) in orders(k)) {
        final q = v[qi], p = v[pi];
        if (qtyOk(q) && p > 0 && t > 0 && _close(q * p, t)) {
          return _Tail(idx[k - 2], q, p, t, unitAfter(idx[qi]), true, exact: true);
        }
      }
    }
  }
  if (m >= 2) {
    final a = v[m - 2], t = v[m - 1];
    final aMoney = _isMoney(tk[idx[m - 2]]);
    // "2 UN 20,00" ou "2 x 20,00": qtd e total
    if (!aMoney && a == a.roundToDouble() && qtyOk(a) && a <= 999 &&
        (unitAfter(idx[m - 2]).isNotEmpty || tk.contains('X'))) {
      return _Tail(idx[m - 2], a, t / a, t, unitAfter(idx[m - 2]), false);
    }
    // "1,50 3,00": preço e total → qtd = total / preço
    // (só com centavos de verdade: "5,000 5,000" é peso, não preço)
    final cents = RegExp(r'[,.]\d{2}$');
    if (aMoney && a > 0 && t > 0 && cents.hasMatch(tk[idx[m - 2]]) && cents.hasMatch(tk[idx[m - 1]])) {
      final q = t / a;
      if ((q - q.round()).abs() < 0.01 && q.round() >= 1 && q.round() <= 999) {
        // preço = total (1 unidade) é só um palpite; 2 ou mais confere a conta
        return _Tail(idx[m - 2], q.roundToDouble(), a, t, '', q.round() >= 2);
      }
    }
  }
  // só o valor
  return _Tail(idx[m - 1], 1, v[m - 1], v[m - 1], '', false);
}

bool _hasLetters(String s) => RegExp(r'[A-Z]{2,}').hasMatch(s);

/// Tira da descrição o nº do item e o código (EAN/código do fornecedor).
(String desc, String code) _splitCode(String raw) {
  final tk = raw.trim().split(RegExp(r'\s+'));
  var code = '';
  var i = 0;
  // "001" (nº do item)
  if (tk.length > 1 && RegExp(r'^\d{1,3}$').hasMatch(tk[0])) i++;
  // EAN ou código: só dígitos (6-14) ou código com dígito antes do nome
  if (i < tk.length - 1 &&
      (RegExp(r'^\d{6,14}$').hasMatch(tk[i]) ||
          (RegExp(r'^[A-Z0-9.\-/]{4,}$').hasMatch(tk[i]) &&
              RegExp(r'\d').hasMatch(tk[i]) &&
              RegExp(r'^[A-Z]{3,}').hasMatch(tk[i + 1])))) {
    code = tk[i];
    i++;
  }
  return (tk.sublist(i).join(' '), code);
}

/// Itens da nota (qualquer layout comum).
List<ReceiptItem> extractReceiptItems(List<String> lines, List<String> up,
    {Set<int>? usedLines}) {
  final found = <(ReceiptItem, bool)>[]; // (item, conta confere)
  var inItems = true;
  for (var i = 0; i < up.length; i++) {
    final l = _fixDigits(up[i]);
    if (_isColumnHeader(l)) {
      inItems = true;
      continue;
    }
    if (l.contains('---') || l.contains('===')) continue;
    final tk = _tokens(l);
    final tail = _readTail(tk);
    if (_notItem.hasMatch(l)) {
      // "OLEO TOTAL QUARTZ 2 UN 45,00 90,00" e "CHAVE DE SETA 1 UN 89,00
      // 89,00" são produtos: a linha tem qtd, preço e total e começa pelo nome
      final product = tail != null &&
          tail.exact &&
          tail.start >= 2 &&
          _hasLetters(tk.take(tail.start).join(' ')) &&
          !_totalStart.hasMatch(l);
      if (!product) {
        if (l.contains('TOTAL')) inItems = false;
        continue;
      }
    }
    if (tail == null || tail.total <= 0) continue;
    usedLines?.add(i);
    // o que sobrou antes da conta é a descrição (sem colunas soltas no fim:
    // NCM, CFOP, "UN"…)
    var end = tail.start;
    while (end > 0 &&
        (_unitWords.contains(tk[end - 1].replaceAll('.', '')) ||
            _fillWords.contains(tk[end - 1]))) {
      end--;
    }
    var nums = 0;
    while (end - nums > 0 && _num(tk[end - 1 - nums]) != null) {
      nums++;
    }
    if (nums >= 2) end -= nums; // colunas da DANFE (NCM, CST, CFOP)
    var head = tk.sublist(0, end).join(' ');
    var item = tail;
    // "2,00 XYZ 41,00 82,00": quantidade e uma unidade desconhecida na
    // frente; a descrição está na linha de cima
    final lead = RegExp(r'^(\d+(?:[.,]\d+)?) ([A-Z]{1,8})$').firstMatch(head);
    if (lead != null && i > 0 && _moneys(up[i - 1]).isEmpty) {
      final q = _num(lead[1]!) ?? 0;
      if (q > 0 && _close(q * tail.unitPrice, tail.total)) {
        item = _Tail(tail.start, q, tail.total / q, tail.total, lead[2]!, true);
        head = '';
      }
    }
    var (desc, code) = _splitCode(head);
    var text = '';
    if (_hasLetters(desc)) {
      // com acentos, da linha original
      text = _splitCode(_descFromOriginal(lines[i], head)).$1;
    } else {
      // linha só com números: a descrição está na linha de cima
      for (var k = i - 1; k >= 0 && k >= i - 2; k--) {
        final prev = _fixDigits(up[k]);
        if (_moneys(prev).isNotEmpty ||
            prev.contains('---') ||
            _notItem.hasMatch(prev) ||
            _isColumnHeader(prev)) {
          break;
        }
        if (!_hasLetters(prev)) continue;
        final (d, c) = _splitCode(lines[k]);
        text = d;
        if (code.isEmpty) code = c;
        break;
      }
      if (text.isEmpty) {
        if (!item.strong) continue;
        text = 'Item';
      }
    }
    if (!item.strong && !inItems) continue;
    found.add((
      ReceiptItem(_cleanDesc(text), item.qty, item.unit,
          double.parse(item.unitPrice.toStringAsFixed(4)), item.total,
          code: code),
      item.strong
    ));
  }
  // com itens "certos" (qtd × preço = total), só entram os palpites que têm
  // quantidade ou unidade (mesma lista); sem nenhum certo, valem os palpites
  // ("PRODUTO 12,00")
  final anyStrong = found.any((e) => e.$2);
  return [
    for (final (it, ok) in found)
      if (ok || !anyStrong || it.qty > 1 || it.unit.isNotEmpty) it
  ];
}

bool _isColumnHeader(String l) =>
    RegExp(r'\b(DESCRI\w*|PRODUTO|QTDE?|ITEM|CODIGO|COD)\b').hasMatch(l) &&
    RegExp(r'\b(VL|VLR|VALOR|PRC|PRECO|TOTAL|UNIT|UNID|QTDE?)\b').hasMatch(l) &&
    _moneys(l).isEmpty;

/// A mesma quantidade de palavras da linha original (com acentos).
String _descFromOriginal(String original, String upDesc) {
  final words = upDesc.split(' ').where((e) => e.isNotEmpty).length;
  final ow = original.trim().split(RegExp(r'\s+'));
  if (ow.length < words) return upDesc;
  return ow.take(words).join(' ');
}
