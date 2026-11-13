// Entrada de material no estoque a partir da nota de compra: foto (OCR),
// XML da NF-e ou PDF (DANFE).

import 'docs.dart';
import 'models.dart';
import 'quote_import.dart' show PdfWord;
import 'receipt_parser.dart';
import 'stock.dart';

/// Lê o XML da NF-e (o arquivo que o fornecedor manda junto da nota).
/// Devolve null se não for uma NF-e.
ReceiptData? parseNfeXml(String xml) {
  if (!xml.contains('<infNFe') && !xml.contains('<NFe')) return null;
  String tag(String src, String name) {
    final m = RegExp('<(?:\\w+:)?$name(?:\\s[^>]*)?>([\\s\\S]*?)</(?:\\w+:)?$name>').firstMatch(src);
    return m == null ? '' : _unescape(m.group(1)!.trim());
  }

  final emit = tag(xml, 'emit');
  final supplier = tag(emit, 'xFant').isNotEmpty ? tag(emit, 'xFant') : tag(emit, 'xNome');
  final ide = tag(xml, 'ide');
  final dt = tag(ide, 'dhEmi').isNotEmpty ? tag(ide, 'dhEmi') : tag(ide, 'dEmi');
  final date = DateTime.tryParse(dt.length >= 10 ? dt.substring(0, 10) : dt);
  final nNF = tag(ide, 'nNF');
  final items = <ReceiptItem>[];
  for (final m in RegExp(r'<(?:\w+:)?det\b[^>]*>([\s\S]*?)</(?:\w+:)?det>').allMatches(xml)) {
    final prod = tag(m.group(1)!, 'prod');
    double n(String t) => double.tryParse(tag(prod, t)) ?? 0;
    final qty = n('qCom');
    final total = n('vProd') - n('vDesc');
    items.add(ReceiptItem(
      tag(prod, 'xProd'),
      qty,
      tag(prod, 'uCom'),
      qty > 0 ? total / qty : n('vUnCom'),
      total,
      code: tag(prod, 'cProd'),
    ));
  }
  final vNF = double.tryParse(tag(tag(xml, 'ICMSTot'), 'vNF')) ?? 0;
  final pag = tag(xml, 'tPag');
  final payment = switch (pag) {
    '01' => 'Dinheiro',
    '03' => 'Cartão de crédito',
    '04' => 'Cartão de débito',
    '15' => 'Boleto',
    '17' => 'Pix',
    _ => '',
  };
  final all = items.map((e) => e.description.toUpperCase()).join(' ');
  return ReceiptData(
    supplier: supplier,
    date: date,
    total: vNF > 0 ? vNF : items.fold(0.0, (a, e) => a + e.total),
    items: items,
    category: _looksLikeMaterial(all) ? ExpenseCategory.materiais : ExpenseCategory.fornecedor,
    rawText: '',
    docNumber: nNF.isEmpty ? '' : 'NF-e $nNF',
    payment: payment,
  );
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'");

/// PDF da nota (DANFE ou orçamento/cupom em PDF): o texto vira linhas e passa
/// pelo mesmo leitor das fotos.
ReceiptData parseReceiptPdfWords(List<PdfWord> words) {
  final byPage = <int, List<OcrPiece>>{};
  for (final w in words) {
    byPage.putIfAbsent(w.page, () => []).add(OcrPiece(w.text, w.x, w.y, w.x1, w.y + 7));
  }
  final lines = <String>[];
  for (final p in (byPage.keys.toList()..sort())) {
    lines.addAll(_joinWords(byPage[p]!));
  }
  return parseReceipt(lines);
}

/// Junta as palavras em linhas, com um espaço entre palavras e três entre
/// colunas (como as linhas do OCR).
List<String> _joinWords(List<OcrPiece> pieces) {
  final sorted = [...pieces]..sort((a, b) {
      final y = a.top.compareTo(b.top);
      return y != 0 ? y : a.left.compareTo(b.left);
    });
  final rows = <List<OcrPiece>>[];
  for (final p in sorted) {
    if (rows.isNotEmpty && (p.top - rows.last.first.top).abs() <= 2.2) {
      rows.last.add(p);
    } else {
      rows.add([p]);
    }
  }
  return [
    for (final r in rows)
      () {
        r.sort((a, b) => a.left.compareTo(b.left));
        final b = StringBuffer(r.first.text);
        for (var i = 1; i < r.length; i++) {
          b.write(r[i].left - r[i - 1].right > 8 ? '   ' : ' ');
          b.write(r[i].text);
        }
        return b.toString();
      }()
  ];
}

const _material = [
  'TINTA', 'VERNIZ', 'PRIMER', 'MASSA', 'LIXA', 'THINNER', 'SOLVENTE',
  'CATALIS', 'ACELERADOR', 'FITA', 'ESTOPA', 'DILUENTE', 'POLIDOR', 'COMPOSTO',
  'CERA', 'FUNDO', 'ADESIVO', 'COLA', 'MASCARAMENTO', 'PAPEL', 'LUVA',
  'DISCO', 'ESMALTE', 'ANTICORROS', 'BASE', 'BOINA', 'PANO', 'SELADOR',
  'DESENGRAX', 'SOLUCAO', 'METALIC', ' MET.', ' MET ', 'PEROLIZ',
];

bool _looksLikeMaterial(String upper) => _material.any(upper.contains);

const _part = [
  'PARA-CHOQUE', 'PARACHOQUE', 'PARA CHOQUE', 'FAROL', 'LANTERNA', 'PORTA ',
  'CAPO', 'PARALAMA', 'PARA-LAMA', 'RETROVISOR', 'GRADE', 'RADIADOR',
  'AMORTECEDOR', 'PASTILHA', 'MACANETA', 'SUPORTE',
];

bool _looksLikePart(String upper) => _part.any(upper.contains);

/// Unidade da nota → unidade do estoque.
String stockUnitFor(String raw) {
  final u = raw.trim().toUpperCase().replaceAll('.', '');
  return switch (u) {
    'L' || 'LT' || 'LTS' || 'LITRO' || 'LITROS' => 'litro',
    'ML' => 'ml',
    'KG' || 'KILO' || 'QUILO' => 'kg',
    'G' || 'GR' => 'g',
    'M' || 'MT' || 'MTS' || 'METRO' => 'm',
    'RL' || 'ROLO' || 'ROLOS' => 'rolo',
    'PR' || 'PAR' => 'par',
    'FL' || 'FLS' || 'FOLHA' || 'FOLHAS' => 'folha',
    'DISCO' || 'DISCOS' => 'disco',
    _ => 'un',
  };
}

/// Embalagem lida na nota: "750GR", "900ML", "1KG", ou "QUART" (lata de
/// 900 ml; o tamanho também pode vir na descrição: "VERNIZ … 900ML").
({double size, String unit, String name})? packFrom(String rawUnit, String desc) {
  final u = rawUnit.trim().toUpperCase();
  ({double size, String unit, String name})? parse(String t, String name) {
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(ML|LTS?|LITROS?|L|KG|GRS?|G)\b').firstMatch(t);
    if (m == null) return null;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    if (n <= 0) return null;
    return switch (m.group(2)!) {
      'ML' => (size: n, unit: 'ml', name: name),
      'KG' => (size: n * 1000, unit: 'g', name: name),
      'G' || 'GR' || 'GRS' => (size: n, unit: 'g', name: name),
      _ => (size: n * 1000, unit: 'ml', name: name), // litro
    };
  }

  final fromUnit = parse(u, 'embalagem');
  if (fromUnit != null) {
    // "1,00 1KG" de massa de polir: pote; "750GR" de massa: lata
    return (size: fromUnit.size, unit: fromUnit.unit, name: fromUnit.unit == 'g' ? 'pote' : 'frasco');
  }
  if (u == 'QUART' || u == 'QT' || u == 'QUARTO') {
    final d = parse(desc.toUpperCase(), 'lata');
    return (size: d?.size ?? 900, unit: d?.unit ?? 'ml', name: 'lata');
  }
  if (u == 'GL' || u == 'GALAO') return (size: 3600, unit: 'ml', name: 'galão');
  return null;
}

/// Uma linha da nota a caminho do estoque (o usuário confere e ajusta).
class StockEntryLine {
  StockEntryLine({
    required this.name,
    required this.code,
    required this.qty,
    required this.unit,
    required this.unitCost,
    required this.kind,
    this.match,
    this.packSize = 0,
    this.packName = '',
    this.itemIndex = -1,
  });

  /// Posição do item na nota (liga a linha ao documento guardado).
  final int itemIndex;

  /// Embalagem (ex.: lata de 900 ml): a nota conta latas e o estoque conta
  /// na unidade de uso. 0 = sem embalagem.
  double packSize;
  String packName;

  String name;
  String code;
  double qty;
  String unit;

  /// Custo de cada unidade da nota (já com desconto).
  double unitCost;
  StockKind kind;

  /// Item do estoque que vai receber a quantidade (null = cria um novo).
  StockItem? match;
  bool include = true;
}

String _key(String s) => normCode(s);

/// Monta as linhas da entrada, achando o item do estoque quando já existe
/// (mesmo código ou mesmo nome).
List<StockEntryLine> planStockEntry(ReceiptData d, List<StockItem> stock) {
  final out = <StockEntryLine>[];
  for (final (index, it) in d.items.indexed) {
    final name = it.description.trim();
    if (name.isEmpty && it.code.isEmpty) continue;
    StockItem? match;
    final code = _key(it.code);
    if (code.isNotEmpty) {
      for (final s in stock) {
        if (s.kind == StockKind.cliente) continue;
        if ([s.partNumber, s.mfrCode, s.sku].any((c) => c.isNotEmpty && _key(c) == code)) {
          match = s;
          break;
        }
      }
    }
    if (match == null && name.isNotEmpty) {
      final k = _key(name);
      for (final s in stock) {
        if (s.kind == StockKind.cliente) continue;
        if (_key(s.name) == k) {
          match = s;
          break;
        }
      }
    }
    final pack = packFrom(it.unit, name);
    final up = name.toUpperCase();
    out.add(StockEntryLine(
      name: name.isEmpty ? it.code : name,
      code: it.code,
      qty: it.qty <= 0 ? 1 : it.qty,
      unit: pack?.unit ?? stockUnitFor(it.unit),
      packSize: pack?.size ?? 0,
      packName: pack?.name ?? '',
      unitCost: it.unitPrice > 0 ? it.unitPrice : (it.qty > 0 ? it.total / it.qty : it.total),
      kind: match?.kind ??
          (_looksLikeMaterial(up) ||
                  (d.category == ExpenseCategory.materiais && !_looksLikePart(up))
              ? StockKind.material
              : StockKind.peca),
      match: match,
      itemIndex: index,
    ));
  }
  return out;
}

/// Aplica a entrada: soma no item que já existe (custo passa a ser o da nota)
/// ou cria um item novo. Cada entrada fica no histórico do item, ligada ao
/// documento guardado ([doc]). Devolve os itens criados.
List<StockItem> applyStockEntry(List<StockEntryLine> lines,
    {String docLabel = '', StoredDoc? doc, DateTime? date}) {
  final created = <StockItem>[];
  final label = docLabel.isNotEmpty
      ? docLabel
      : (doc == null
          ? ''
          : [doc.party, doc.number].where((e) => e.isNotEmpty).join(' · '));
  for (final l in lines) {
    if (!l.include || l.qty <= 0) continue;
    var s = l.match;
    final double added;
    if (s != null) {
      if (s.hasPack) {
        // a nota fala em embalagens (latas, caixas…); o estoque conta na
        // unidade de uso (ml, folha…)
        added = l.qty * s.packSize;
        if (l.unitCost > 0) {
          s.packCost = l.unitCost;
          s.syncPackCost();
        }
      } else if (l.packSize > 0 && s.unit == l.unit) {
        // item cadastrado direto em ml/g e a nota vem em latas/potes
        added = l.qty * l.packSize;
        if (l.unitCost > 0) s.cost = l.unitCost / l.packSize;
      } else {
        added = l.qty;
        if (l.unitCost > 0) s.cost = l.unitCost;
      }
      s.qty += added;
      if (s.partNumber.isEmpty && l.code.isNotEmpty && s.kind == StockKind.peca) {
        s.partNumber = l.code;
      }
    } else {
      final pack = l.packSize > 0;
      added = pack ? l.qty * l.packSize : l.qty;
      s = StockItem(
        kind: l.kind,
        name: l.name,
        partNumber: l.kind == StockKind.peca ? l.code : '',
        qty: added,
        unit: l.unit,
        cost: pack ? l.unitCost / l.packSize : l.unitCost,
        packName: pack ? l.packName : 'lata',
        packSize: pack ? l.packSize : 0,
        packCost: pack ? l.unitCost : 0,
      );
      if (l.kind == StockKind.material && l.code.isNotEmpty) s.mfrCode = l.code;
      created.add(s);
    }
    s.ins.add(StockIn(
      date: date ?? doc?.date,
      qty: added,
      noteQty: l.qty,
      unitCost: l.unitCost,
      docId: doc?.id ?? '',
      label: label,
    ));
    if (doc != null && l.itemIndex >= 0 && l.itemIndex < doc.items.length) {
      doc.items[l.itemIndex].stockId = s.id;
    }
  }
  return created;
}
