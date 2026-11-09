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
  if (_isSoma(full)) return _parseSoma(words, rows);
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
        // o valor fica nas linhas logo abaixo (pode haver outra coluna com
        // texto em duas linhas no meio)
        for (var j = i + 1; j < rows.length; j++) {
          final n = rows[j];
          if (n.page != r.page || n.y - r.y > 16) break;
          for (final v in n.segs) {
            if ((v.x - s.x).abs() < 4) return (s.text, _clean(v.text));
          }
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


// ======================================================================
// Porto Seguro / Azul / Itaú — "Orçamento Detalhado" do sistema SOMA
// (relatório Jasper). Números no formato americano (2,345.10).

bool _isSoma(String full) =>
    full.contains('PEÇAS - TROCA') ||
    full.contains('PEÇAS - RECUPERAR') ||
    full.contains('MONTAGEM - DESMONTAGEM') ||
    (full.contains('DETALHADO') && full.contains('Licença:'));

/// "2,345.10" → 2345.10; "14.00" → 14.
double? parseUsNumber(String raw) {
  final m = RegExp(r'-?\d[\d,]*(\.\d+)?').firstMatch(raw.replaceAll('R\$', ''));
  if (m == null) return null;
  return double.tryParse(m.group(0)!.replaceAll(',', ''));
}

final _usNum = RegExp(r'^\d{1,3}(,\d{3})*(\.\d+)?$|^\d+(\.\d+)?$');

/// "(MOLDURA INF.P/CHOQUE TRAS) - Val. 2015/" → ("MOLDURA INF.P/CHOQUE TRAS",
/// "Val. 2015/"); "REFLETOR REFLETOR REFLETOR P/CHOQUE" → "REFLETOR P/CHOQUE".
(String, String) _somaDesc(String raw) {
  var t = raw.trim();
  var note = '';
  final v = RegExp(r'\s+-\s+(Val\..*)$').firstMatch(t);
  if (v != null) {
    note = v.group(1)!.replaceAll(RegExp(r'\s*\*\s*$'), '').trim();
    t = t.substring(0, v.start).trim();
  }
  t = t.replaceAll(RegExp(r'^\(\d+\)\s*'), '').replaceAll(RegExp(r'\s*\*$'), '');
  if (t.startsWith('(') && t.endsWith(')')) t = t.substring(1, t.length - 1);
  if (t.startsWith('(') && !t.contains(')')) t = t.substring(1);
  final out = <String>[];
  for (final w in t.split(RegExp(r'\s+'))) {
    if (out.isNotEmpty && out.last == w) continue;
    out.add(w);
  }
  return (out.join(' ').trim(), note == 'Val.' ? '' : note);
}

ImportedQuote _parseSoma(List<PdfWord> words, List<_Row> rows) {
  final c = Claim(status: ClaimStatus.orcamento, type: ClaimType.seguradora);
  final q = ImportedQuote(c, system: 'Porto (SOMA)');

  // ---- cabeçalho "Rótulo: valor" (o valor fica à direita, quase na mesma
  // altura do rótulo)
  final head = words.where((w) => w.page == 0 && w.y < 185).toList();
  String label(String name, {bool left = true}) {
    for (final l in head) {
      if (l.text != name) continue;
      if (left && l.x > 300 || !left && l.x < 300) continue;
      final limit = left ? 350.0 : 1000.0;
      final vals = head
          .where((w) => (w.y - l.y).abs() <= 3.5 && w.x > l.x1 - 0.5 && w.x < limit && w != l)
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      final out = <String>[];
      for (final w in vals) {
        if (w.text.endsWith(':') && out.isNotEmpty) break; // próximo rótulo
        if (w.text.endsWith(':')) continue;
        out.add(w.text);
      }
      return out.join(' ').trim();
    }
    return '';
  }

  final v = c.vehicle;
  c.claimNumber = label('Sinistro:');
  c.policyNumber = label('Apólice:');
  c.customerName = label('Segurado:');
  c.customerPhone = label('Telefone:');
  final veh = label('Veículo:').replaceAll(RegExp(r'[\s-]+$'), '');
  if (veh.isNotEmpty) {
    final parts = veh.split(' ');
    if (_brands.contains(parts.first.toUpperCase()) && parts.length > 1) {
      v.brand = parts.first;
      v.model = parts.sublist(1).join(' ');
    } else {
      v.model = veh;
    }
  }
  v.chassis = label('Chassi:').toUpperCase();
  v.plate = label('Licença:').toUpperCase();
  v.color = label('Impregnação:');
  if (v.color.isEmpty) v.color = label('Cor:');
  final fab = label('Fabricação:');
  final mod = label('Modelo:');
  v.year = [fab, mod].where((e) => e.isNotEmpty).toSet().join('/');
  final kmW = head.where((w) => w.text.startsWith('Atual:')).toList();
  if (kmW.isNotEmpty) {
    var k = kmW.first.text.substring(6);
    if (k.isEmpty) k = label('Atual:');
    final n = parseUsNumber(k);
    if (n != null && n > 1) v.km = n.round().toString();
  }
  final emp = label('Empresa:', left: false);
  c.insurerName = emp.contains(' - ') ? emp.substring(emp.indexOf(' - ') + 3).trim() : emp;
  final autor = label('Autor:', left: false);
  c.regulatorName = autor.replaceFirst(RegExp(r'^\d+\s*-\s*'), '');
  final notes = <String>[];
  final num = label('Orçamento:', left: false);
  final ver = label('Versão:', left: false);
  if (num.isNotEmpty) {
    notes.add('Orçamento ${q.system}: $num${ver.isEmpty ? '' : ' (versão $ver)'}');
  }

  // ---- situação, índices, franquia e total
  for (final r in rows) {
    final t = r.text;
    final sit = RegExp(r'^ORÇAMENTO \d+ - .* - ([A-ZÇÃÕÉ ]+)$').firstMatch(t);
    if (sit != null && notes.every((n) => !n.startsWith('Situação'))) {
      notes.add('Situação na seguradora: ${sit.group(1)!.trim()}');
    }
    final fr = RegExp(r'-\(\$\s*([\d,]+\.\d{2})\)').firstMatch(t);
    if (fr != null && c.deductible == 0) c.deductible = parseUsNumber(fr.group(1)!) ?? 0;
    final lr = RegExp(r'Funilaria\s+R\$\s*([\d,]+\.\d+)').firstMatch(t);
    if (lr != null && c.laborRate == 0) c.laborRate = parseUsNumber(lr.group(1)!) ?? 0;
    final pr = RegExp(r'^Pintura\s+R\$\s*([\d,]+\.\d+)').firstMatch(t);
    if (pr != null && c.paintRate == 0) c.paintRate = parseUsNumber(pr.group(1)!) ?? 0;
    final dc = RegExp(r'^Funilaria\s+([\d.]+)\s*%').firstMatch(t);
    if (dc != null && q.partsDiscountPct == 0) q.partsDiscountPct = parseUsNumber(dc.group(1)!) ?? 0;
  }
  for (var i = 0; i < rows.length && q.pdfTotal == 0; i++) {
    if (!rows[i].text.contains('Total do Orçamento')) continue;
    for (var j = i; j < rows.length && rows[j].page == rows[i].page && rows[j].y - rows[i].y < 20; j++) {
      final m = RegExp(r'R\$\s*([\d,]+\.\d{2})').firstMatch(rows[j].text);
      if (m != null) {
        q.pdfTotal = parseUsNumber(m.group(1)!) ?? 0;
        break;
      }
    }
  }

  // ---- itens
  String section = '';
  BudgetItem? last;
  for (final r in rows) {
    final t = r.text;
    if (t.startsWith('RESUMO') || t.startsWith('ANOTAÇÕES') || t.startsWith('ÍNDICES')) {
      section = '';
      continue;
    }
    if (t.contains('PEÇAS - TROCA') && t.length < 30) {
      section = 'troca';
      continue;
    }
    if (t.contains('PEÇAS - RECUPERAR') && t.length < 30) {
      section = 'recuperar';
      continue;
    }
    if (t.contains('MONTAGEM - DESMONTAGEM') && t.length < 35) {
      section = 'md';
      continue;
    }
    if (section.isEmpty) continue;
    if (t.startsWith('Código') || t.startsWith('Total:') || RegExp(r'Page \d+ of \d+').hasMatch(t)) {
      continue;
    }
    final ws = [...r.words]..sort((a, b) => a.x.compareTo(b.x));
    if (ws.isEmpty) continue;
    final first = ws.first;
    // números do fim da linha
    final nums = <double>[];
    var k = ws.length;
    while (k > 1 && _usNum.hasMatch(ws[k - 1].text)) {
      k--;
    }
    for (var i = k; i < ws.length; i++) {
      nums.add(parseUsNumber(ws[i].text) ?? 0);
    }
    if (first.x > 250) continue; // linha de totais da seção

    final need = switch (section) { 'troca' => 6, 'recuperar' => 6, _ => 3 };
    final isItem = first.x < 45 && nums.length >= need && k >= 2;
    final isSub = section == 'troca' && first.x >= 60 && RegExp(r'^\d+$').hasMatch(first.text) && nums.length >= 2 && k >= 2;
    if (!isItem && !isSub) {
      // continuação da descrição do item de cima
      if (last != null && first.x >= 60 && nums.isEmpty) {
        final extra = ws.map((w) => w.text).join(' ').trim();
        if (extra.isNotEmpty && extra != '*') {
          last.note = [last.note, extra].where((e) => e.isNotEmpty).join(' ');
        }
      }
      continue;
    }
    final take = isSub ? 2 : need;
    final tail = nums.sublist(nums.length - take);
    final code = first.text;
    final (desc, note) =
        _somaDesc(ws.sublist(1, ws.length - take).map((w) => w.text).join(' '));
    if (isSub) {
      final it = BudgetItem(
        op: ItemOp.reparo,
        description: desc.isEmpty ? 'Montagem/desmontagem' : desc,
        partNumber: code,
        removeInstall: true,
        laborHours: tail[0],
        paintHours: tail[1],
      );
      c.items.add(it);
      last = it;
      continue;
    }
    switch (section) {
      case 'troca':
        final it = BudgetItem(
          op: ItemOp.troca,
          description: desc,
          partNumber: code,
          qty: tail[0] <= 0 ? 1 : tail[0],
          price: tail[1],
          discountPct: tail[2],
          laborHours: tail[4],
          paintHours: tail[5],
          note: note,
        );
        c.items.add(it);
        last = it;
      case 'recuperar':
        final restaurar = tail[5];
        final hasWork = tail[1] > 0 || tail[3] > 0;
        if (hasWork) {
          final it = BudgetItem(
            op: ItemOp.reparo,
            description: desc,
            partNumber: code,
            qty: tail[0] <= 0 ? 1 : tail[0],
            laborHours: tail[1],
            paintHours: tail[3],
            note: note,
          );
          c.items.add(it);
          last = it;
        }
        if (restaurar > 0) {
          final it = BudgetItem(
            op: ItemOp.servico,
            description: hasWork ? 'Restaurar $desc' : desc,
            partNumber: code,
            price: restaurar,
            note: ['Restaurar', note].where((e) => e.isNotEmpty).join(' · '),
          );
          c.items.add(it);
          last = it;
        }
      default:
        final it = BudgetItem(
          op: ItemOp.reparo,
          description: desc,
          partNumber: code,
          qty: tail[0] <= 0 ? 1 : tail[0],
          removeInstall: true,
          laborHours: tail[1],
          note: note,
        );
        c.items.add(it);
        last = it;
    }
  }

  if (notes.isNotEmpty) c.notes = notes.join('\n');
  if (c.items.isEmpty) q.warnings.add('Nenhum item foi encontrado nas tabelas de peças.');
  return q;
}
