// Leitura de orçamentos de seguradora em PDF (Cilia e parecidos).
//
// O PDF vira uma lista de palavras com posição (página, x, y). Daqui para
// frente é só Dart puro: as palavras são juntadas em linhas e colunas e os
// campos são lidos pelo rótulo ("Placa", "Chassi"…) e pela tabela de itens
// ("OPERAÇÕES  QTD.  CÓDIGO  TIPO  TÍTULO …").

import 'models.dart';

/// Uma palavra do PDF com a posição (pontos, origem no canto de cima).
class PdfWord {
  const PdfWord(this.page, this.text, this.x, this.y, this.x1);
  final int page;
  final String text;
  final double x;
  final double y;
  final double x1;

  factory PdfWord.fromJson(Map<String, dynamic> j) => PdfWord(
        (j['p'] as num).toInt(),
        '${j['t']}',
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['x1'] as num).toDouble(),
      );
}

/// Resultado da leitura: o orçamento montado e o que vale conferir.
class ImportedQuote {
  ImportedQuote(this.claim, {required this.system});
  final Claim claim;

  /// Sistema reconhecido (ex.: Cilia) ou vazio quando não reconheceu.
  final String system;

  /// Total que o próprio PDF informa (0 = não achou).
  double pdfTotal = 0;

  /// Desconto padrão das peças informado no cabeçalho.
  double partsDiscountPct = 0;

  /// Avisos para a tela de conferência.
  final List<String> warnings = [];

  bool get recognized => system.isNotEmpty;
}

class _Seg {
  _Seg(this.text, this.x, this.x1);
  String text;
  final double x;
  double x1;
}

class _Row {
  _Row(this.page, this.y);
  final int page;
  final double y;
  final List<PdfWord> words = [];
  List<_Seg> segs = const [];
  String get text => segs.map((e) => e.text).join(' ');
}

List<_Row> _rows(List<PdfWord> all) {
  final words = all.where((w) => w.text.trim().isNotEmpty).toList()
    ..sort((a, b) {
      final p = a.page.compareTo(b.page);
      if (p != 0) return p;
      final y = a.y.compareTo(b.y);
      return y != 0 ? y : a.x.compareTo(b.x);
    });
  final rows = <_Row>[];
  for (final w in words) {
    final last = rows.isEmpty ? null : rows.last;
    if (last != null && last.page == w.page && (w.y - last.y).abs() <= 2.2) {
      last.words.add(w);
    } else {
      rows.add(_Row(w.page, w.y)..words.add(w));
    }
  }
  for (final r in rows) {
    r.words.sort((a, b) => a.x.compareTo(b.x));
    final segs = <_Seg>[];
    for (final w in r.words) {
      final t = w.text.trim();
      if (segs.isNotEmpty) {
        final s = segs.last;
        final gap = w.x - s.x1;
        if (gap < 0.8) {
          s.text += t;
          if (w.x1 > s.x1) s.x1 = w.x1;
          continue;
        }
        if (gap < 7) {
          s.text += ' $t';
          if (w.x1 > s.x1) s.x1 = w.x1;
          continue;
        }
      }
      segs.add(_Seg(t, w.x, w.x1));
    }
    r.segs = segs;
  }
  return rows;
}

/// Converte "R$ 1.500,05", "26,00%", "69,77/h", "0,50" e "128394.0".
double? parseBrNumber(String raw) {
  final s = raw.replaceAll('R\$', '').replaceAll('%', '').replaceAll('/h', '').trim();
  final m = RegExp(r'-?\d[\d.]*(,\d+)?').firstMatch(s);
  if (m == null) return null;
  var t = m.group(0)!;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if ('.'.allMatches(t).length > 1 ||
      RegExp(r'\.\d{3}$').hasMatch(t) && !RegExp(r'\.\d$').hasMatch(t)) {
    t = t.replaceAll('.', ''); // 50.210 (milhar)
  }
  return double.tryParse(t);
}

String _clean(String v) {
  final t = v.trim();
  return t == '-' || t == '—' ? '' : t;
}

bool _isLabel(String seg, String label) {
  final s = seg.toLowerCase();
  final l = label.toLowerCase();
  if (!s.startsWith(l)) return false;
  if (s.length == l.length) return true;
  final next = s[l.length];
  return !RegExp(r'[a-zà-ú0-9]').hasMatch(next);
}

/// Lê um orçamento de seguradora a partir das palavras do PDF.
ImportedQuote parseInsurerQuote(List<PdfWord> words) {
  final rows = _rows(words);
  final full = rows.map((r) => r.text).join('\n');
  final isCilia = RegExp(r'cilia', caseSensitive: false).hasMatch(full);
  final hasTable = rows.any((r) => r.text.contains('OPERAÇÕES') && r.text.contains('TÍTULO'));
  final c = Claim(status: ClaimStatus.orcamento);
  final q = ImportedQuote(c,
      system: isCilia ? 'Cilia' : (hasTable ? 'Seguradora' : ''));

  // valor que fica logo abaixo do rótulo, na mesma coluna
  (String, String)? field(String label) {
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      for (final s in r.segs) {
        if (!_isLabel(s.text, label)) continue;
        if (i + 1 >= rows.length) return (s.text, '');
        final n = rows[i + 1];
        if (n.page != r.page || n.y - r.y > 16) return (s.text, '');
        for (final v in n.segs) {
          if ((v.x - s.x).abs() < 4) return (s.text, _clean(v.text));
        }
        return (s.text, '');
      }
    }
    return null;
  }

  String val(String label) => field(label)?.$2 ?? '';

  // ---- veículo
  final v = c.vehicle;
  v.plate = val('Placa').toUpperCase();
  v.color = val('Cor');
  v.chassis = val('Chassi').toUpperCase();
  final km = parseBrNumber(val('Quilometragem'));
  v.km = km == null || km <= 0 ? '' : km.round().toString();
  v.fuel = val('Combustível');
  final fipe = field('Valor Fipe');
  if (fipe != null) {
    v.fipeValue = parseBrNumber(fipe.$2) ?? 0;
    final code = RegExp(r'\(([\d-]+)\)').firstMatch(fipe.$1);
    if (code != null) v.fipeCode = code.group(1)!;
  }
  // título: "RCF - CHEVROLET - ONIX (2017 A 2019) JOY 1.0 8V FLEX 2019 …"
  final firstRow = rows.isEmpty ? null : rows.first;
  if (firstRow != null && firstRow.text.contains(' - ')) {
    final parts = firstRow.text.split(' - ').map((e) => e.trim()).toList();
    var bi = parts.indexWhere((p) => _brands.contains(p.toUpperCase()));
    if (bi < 0 && parts.length >= 3) bi = 1;
    if (bi < 0 && parts.length == 2) bi = 0;
    if (bi >= 0 && bi < parts.length - 1) {
      v.brand = parts[bi];
      var model = parts.sublist(bi + 1).join(' - ');
      final years = RegExp(r'\b(19[5-9]\d|20[0-4]\d)\b').allMatches(model).toList();
      if (years.isNotEmpty) {
        final y = years.last;
        v.year = y.group(1)!;
        // o ano final (fora de parênteses) fecha o nome do modelo
        final before = model.substring(0, y.start);
        if ('('.allMatches(before).length == ')'.allMatches(before).length) {
          model = before.trim();
        }
      }
      v.model = model;
    }
  }
  if (v.plate.isEmpty) {
    final m = RegExp(r'\b([A-Z]{3}-?\d[A-Z0-9]\d{2})\b').firstMatch(full);
    if (m != null) v.plate = m.group(1)!;
  }
  if (v.chassis.isEmpty) {
    final m = RegExp(r'\b([A-HJ-NPR-Z0-9]{17})\b').firstMatch(full);
    if (m != null) v.chassis = m.group(1)!;
  }

  // ---- seguro e pessoa
  c.insurerName = val('Seguradora');
  c.claimNumber = val('Sinistro');
  c.policyNumber = val('Apólice');
  final ded = parseBrNumber(val('Franquia'));
  if (ded != null) c.deductible = ded;
  final third = field('Terceiro');
  final insured = field('Segurado');
  if (third != null && third.$2.isNotEmpty) {
    c.type = ClaimType.terceiro;
    c.customerName = third.$2;
  } else if (insured != null && insured.$2.isNotEmpty) {
    c.type = ClaimType.seguradora;
    c.customerName = insured.$2;
  } else {
    final name = val('Cliente');
    if (name.isNotEmpty) c.customerName = name;
    c.type = c.insurerName.isEmpty ? ClaimType.particular : ClaimType.seguradora;
  }
  c.customerDoc = val('CPF/CNPJ');
  c.customerPhone = val('Telefone');
  c.customerEmail = val('E-mail');

  // regulador: "Fluxo: 1 | Criado por: Fulano • SM Reguladora | …"
  for (final r in rows) {
    final m = RegExp(r'Criado por:\s*([^|•]+?)\s*•\s*([^|]+?)\s*(\||$)').firstMatch(r.text);
    if (m == null) continue;
    final who = m.group(1)!.trim();
    final org = m.group(2)!.trim();
    if (who.toLowerCase() == 'webservice') continue;
    if (c.insurerName.isNotEmpty && org.toLowerCase() == c.insurerName.toLowerCase()) continue;
    c.regulatorName = org.isEmpty ? who : '$who ($org)';
    break;
  }

  // ---- valores da hora
  final labor = parseBrNumber(val('Mão de obra')) ?? parseBrNumber(val('Reparação'));
  if (labor != null && labor > 0) c.laborRate = labor;
  final paint = parseBrNumber(val('Pintura'));
  if (paint != null && paint > 0) c.paintRate = paint;
  q.partsDiscountPct = parseBrNumber(val('Desconto')) ?? 0;

  // ---- notas
  final notes = <String>[];
  final quoteNo = val('Orçamento');
  if (quoteNo.isNotEmpty) {
    notes.add('Orçamento ${q.system.isEmpty ? 'importado' : q.system}: $quoteNo');
  }
  final insp = val('Número da Vistoria');
  if (insp.isNotEmpty) notes.add('Vistoria: $insp');
  for (final r in rows) {
    final m = RegExp(r'Tipo de Conclusão:\s*([^|]+)').firstMatch(r.text);
    if (m != null) {
      notes.add('Conclusão da seguradora: ${m.group(1)!.trim()}');
      break;
    }
  }

  // ---- itens
  _parseItems(rows, q);
  if (notes.isNotEmpty) c.notes = notes.join('\n');

  // total que o PDF informa, para conferir
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i].text.contains('Total Geral')) continue;
    final m = RegExp(r'Total Geral\s+R\$\s*([\d.,]+)').firstMatch(rows[i].text);
    if (m != null) {
      q.pdfTotal = parseBrNumber(m.group(1)!) ?? 0;
      break;
    }
  }
  if (q.pdfTotal == 0) {
    for (final r in rows) {
      if (!r.text.startsWith('Total')) continue;
      final m = RegExp(r'R\$\s*([\d.,]+)\s*$').firstMatch(r.text);
      if (m != null) q.pdfTotal = parseBrNumber(m.group(1)!) ?? 0;
    }
  }

  if (!q.recognized) {
    q.warnings.add('Formato de PDF não reconhecido: foi lido só o que deu (placa, chassi). Confira e complete à mão.');
  }
  if (q.recognized && c.items.isEmpty) {
    q.warnings.add('Nenhum item foi encontrado na tabela de peças.');
  }
  return q;
}

const _colKeys = ['QTD', 'CÓDIGO', 'TIPO', 'TÍTULO', 'FORNECIMENTO', 'PREÇO LÍQUIDO', 'PREÇO', 'DESCONTO'];

class _Anchor {
  _Anchor(this.row, this.cells);
  final _Row row;
  final Map<String, String> cells;
  final List<(double, String)> title = [];
}

void _parseItems(List<_Row> rows, ImportedQuote q) {
  final c = q.claim;
  Map<String, double>? cols;
  final anchors = <_Anchor>[];
  final loose = <(_Row, String)>[];
  var inTable = false;

  String colOf(double x) {
    var best = 'OPS';
    final sorted = cols!.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    for (final e in sorted) {
      if (x >= e.value - 3) best = e.key;
    }
    return best;
  }

  for (final r in rows) {
    final t = r.text;
    if (t.contains('OPERAÇÕES') && t.contains('TÍTULO')) {
      final found = <String, double>{};
      for (final s in r.segs) {
        for (final k in _colKeys) {
          if (s.text.toUpperCase().startsWith(k) && !found.containsKey(k)) {
            found[k] = s.x;
            break;
          }
        }
        // "PREÇO DESCONTO PREÇO LÍQUIDO" pode vir junto num pedaço só
      }
      if (found.containsKey('QTD') && found.containsKey('TÍTULO')) {
        cols = found;
        inTable = true;
      }
      continue;
    }
    if (!inTable || cols == null) continue;
    if (t.startsWith('Troca / R&I') ||
        t.contains('LEGENDAS') ||
        t.contains('RESUMO GERAL') ||
        t.startsWith('Status do Orçamento') ||
        t.startsWith('Totais em')) {
      inTable = false;
      continue;
    }
    if (t.startsWith('ITENS DO TIPO') || t.startsWith('ÁREA DE')) continue;
    // cada palavra vai para a coluna em que começa (colunas coladas não se
    // misturam)
    final cells = <String, String>{};
    final lastX1 = <String, double>{};
    for (final w in r.words) {
      final k = w.x < cols['QTD']! - 3 ? 'OPS' : colOf(w.x);
      final prev = cells[k];
      final t = w.text.trim();
      if (prev == null) {
        cells[k] = t;
      } else {
        cells[k] = w.x - (lastX1[k] ?? w.x) < 0.8 ? '$prev$t' : '$prev $t';
      }
      lastX1[k] = w.x1;
    }
    final qty = cells['QTD'] ?? '';
    if (RegExp(r'^\d+([.,]\d+)?$').hasMatch(qty)) {
      anchors.add(_Anchor(r, cells));
    } else if ((cells['TÍTULO'] ?? '').isNotEmpty) {
      loose.add((r, cells['TÍTULO']!));
    }
  }

  // linhas soltas do título (nome em duas linhas) vão para o item mais perto
  for (final (r, text) in loose) {
    _Anchor? best;
    var dist = double.infinity;
    for (final a in anchors) {
      if (a.row.page != r.page) continue;
      final d = (a.row.y - r.y).abs();
      if (d < dist) {
        dist = d;
        best = a;
      }
    }
    if (best != null && dist < 14) best.title.add((r.y, text));
  }

  for (final a in anchors) {
    final parts = [(a.row.y, a.cells['TÍTULO'] ?? ''), ...a.title]
      ..sort((x, y) => x.$1.compareTo(y.$1));
    final title = parts.map((e) => e.$2).where((e) => e.isNotEmpty).join(' ').trim();
    final it = _itemFrom(a.cells, title, q);
    if (it != null) c.items.add(it);
  }
}

BudgetItem? _itemFrom(Map<String, String> cells, String title, ImportedQuote q) {
  // descrição + observação entre parênteses
  var desc = title;
  var note = '';
  final p = title.indexOf('(');
  if (p > 0) {
    desc = title.substring(0, p).trim();
    note = title.substring(p).trim();
  }
  if (desc.isEmpty) desc = title.isEmpty ? 'Item importado' : title;

  // operações: "T", "R&I 0,50", "R 2,00", "P 3,00", "S"
  double t = 0, ri = 0, r = 0, pt = 0;
  var hasT = false, hasRi = false, hasR = false, hasS = false;
  final ops = RegExp(r'(R&I|T|R|P|S)(?:\s+(\d+(?:[.,]\d+)?))?')
      .allMatches(cells['OPS'] ?? '');
  for (final m in ops) {
    final h = m.group(2) == null ? 0.0 : (parseBrNumber(m.group(2)!) ?? 0);
    switch (m.group(1)) {
      case 'T':
        hasT = true;
        t += h;
      case 'R&I':
        hasRi = true;
        ri += h;
      case 'R':
        hasR = true;
        r += h;
      case 'P':
        pt += h;
      case 'S':
        hasS = true;
    }
  }

  final qty = parseBrNumber(cells['QTD'] ?? '') ?? 1;
  final price = parseBrNumber(cells['PREÇO'] ?? '') ?? 0;
  final net = parseBrNumber(cells['PREÇO LÍQUIDO'] ?? '');
  final discRaw = cells['DESCONTO'] ?? '';
  var disc = 0.0;
  if (price > 0) {
    if (net != null && net > 0 && net <= price * (qty <= 0 ? 1 : qty) + 0.01) {
      disc = (1 - net / (price * (qty <= 0 ? 1 : qty))) * 100;
    } else if (discRaw.contains('%')) {
      disc = parseBrNumber(discRaw) ?? 0;
    } else if (q.partsDiscountPct > 0 && _clean(discRaw).isEmpty) {
      disc = q.partsDiscountPct;
    }
  }
  disc = (disc * 100).round() / 100;
  if (disc < 0.01) disc = 0;

  final supplier = _clean(cells['FORNECIMENTO'] ?? '');
  final byInsurer = supplier.toLowerCase().startsWith('segurad');

  final it = BudgetItem(
    description: desc,
    partNumber: _clean(cells['CÓDIGO'] ?? ''),
    qty: qty <= 0 ? 1 : qty,
    note: note,
    origin: switch (_clean(cells['TIPO'] ?? '').toUpperCase()) {
      'PG' => PartOrigin.genuina,
      'PO' => PartOrigin.original,
      'PC' => PartOrigin.paralela,
      'PV' || 'PU' || 'PR' => PartOrigin.usada,
      _ => PartOrigin.nenhuma,
    },
    supplier: supplier == 'Oﬁcina' ? 'Oficina' : supplier,
  );
  if (hasT || (price > 0 && !hasS)) {
    it.op = ItemOp.troca;
    it.price = byInsurer ? 0 : price;
    it.discountPct = byInsurer ? 0 : disc;
    it.laborHours = t + ri + r; // horas de reparação (tirar e colocar)
    it.paintHours = pt;
    if (byInsurer && price > 0) {
      it.note = [it.note, 'Peça fornecida pela seguradora (${price.toStringAsFixed(2).replaceAll('.', ',')})']
          .where((e) => e.isNotEmpty)
          .join(' · ');
    }
  } else if (hasS) {
    it.op = ItemOp.servico;
    it.price = price;
    it.discountPct = disc;
    it.laborHours = ri + r;
  } else if (hasRi || hasR) {
    it.op = ItemOp.reparo;
    it.removeInstall = hasRi;
    it.alsoRepair = hasRi && hasR;
    it.laborHours = ri + r;
    it.paintHours = pt;
  } else if (pt > 0) {
    it.op = ItemOp.pintura;
    it.paintHours = pt;
  } else {
    return null;
  }
  return it;
}

const _brands = {
  'CHEVROLET', 'GM', 'FIAT', 'VOLKSWAGEN', 'VW', 'FORD', 'TOYOTA', 'HONDA',
  'HYUNDAI', 'RENAULT', 'NISSAN', 'JEEP', 'PEUGEOT', 'CITROEN', 'CITROËN',
  'MITSUBISHI', 'KIA', 'BMW', 'MERCEDES-BENZ', 'MERCEDES', 'AUDI', 'CAOA CHERY',
  'CHERY', 'BYD', 'GWM', 'VOLVO', 'LAND ROVER', 'SUZUKI', 'SUBARU', 'RAM',
  'DODGE', 'JAC', 'LIFAN', 'PORSCHE', 'MINI', 'YAMAHA', 'IVECO', 'SCANIA',
  'TROLLER', 'SMART', 'JAGUAR', 'LEXUS',
};
