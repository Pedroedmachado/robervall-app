import 'format.dart';
import 'models.dart';

/// Tipo de item do estoque.
enum StockKind {
  peca('Peça'),
  material('Insumo / material'),
  cliente('Peça de cliente');

  const StockKind(this.label);
  final String label;
}

/// Peça ou material guardado na oficina.
class StockItem {
  String id;
  StockKind kind;
  String name;
  String partNumber;

  /// Para quais carros serve (ex.: "Gol G5 2009-2012").
  String fits;
  double qty;
  String unit;

  /// Quanto custou cada unidade de uso (ex.: por ml). Com embalagem é
  /// calculado: preço da embalagem ÷ conteúdo.
  double cost;

  /// Embalagem em que é comprado (ex.: lata de 900 ml por R\$ 41).
  /// [packSize] = 0: sem embalagem (compra e usa na mesma unidade).
  String packName;
  double packSize;
  double packCost;

  /// Quanto cobrar no orçamento (0 = usa o custo).
  double price;
  /// Endereço: corredor > prateleira > nicho. [location] é texto livre.
  String corridor;
  String shelf;
  String slot;
  String location;
  String notes;

  /// Peça de cliente: sinistro do carro dono da peça.
  String claimId;

  /// Peças: código interno (P-0001), marca/fabricante da peça, código do
  /// fabricante, condição e os carros em que serve. [partNumber] é o código
  /// OEM (número original da montadora).
  String sku;
  String mfrBrand;
  String mfrCode;
  String condition; // original, genuina, paralela, usada ('' = não informado)
  List<VehicleFit> applications;

  /// Foto (arquivo na pasta de fotos).
  String photo;

  StockItem({
    String? id,
    this.kind = StockKind.peca,
    this.name = '',
    this.partNumber = '',
    this.fits = '',
    this.qty = 1,
    this.unit = 'un',
    this.cost = 0,
    this.packName = 'lata',
    this.packSize = 0,
    this.packCost = 0,
    this.price = 0,
    this.corridor = '',
    this.shelf = '',
    this.slot = '',
    this.location = '',
    this.notes = '',
    this.photo = '',
    this.claimId = '',
    this.sku = '',
    this.mfrBrand = '',
    this.mfrCode = '',
    this.condition = '',
    List<VehicleFit>? applications,
  })  : id = id ?? newId(),
        applications = applications ?? [];

  /// Resumo da aplicação: "VW Gol 2013–2016 · Fiat Uno 2010–2014".
  String get applicationLabel => applications.isEmpty
      ? fits
      : applications.map((a) => a.label).join(' · ');

  /// "Corredor 1 · Prateleira B5 · Nicho 3" (ou o texto livre).
  String get address {
    final parts = [
      if (corridor.trim().isNotEmpty) 'Corredor ${corridor.trim()}',
      if (shelf.trim().isNotEmpty) 'Prateleira ${shelf.trim()}',
      if (slot.trim().isNotEmpty) 'Nicho ${slot.trim()}',
      if (location.trim().isNotEmpty) location.trim(),
    ];
    return parts.join(' · ');
  }

  bool get hasPack => packSize > 0;

  /// Quantas embalagens dá o estoque atual.
  double get packs => hasPack ? qty / packSize : 0;

  /// Lixa (folha que se corta em 4, ou disco).
  bool get isSandpaper =>
      name.toLowerCase().contains('lixa') || unit == 'disco';

  /// "900 ml (1 lata)", "2 e 3/4 folhas" ou "3 un".
  String get qtyLabel =>
      '${qtyText(qty, unit)}${hasPack ? ' (${num2(packs)} ${packs < 2 ? packName : _plural(packName)})' : ''}';

  /// Recalcula o custo por unidade a partir da embalagem.
  void syncPackCost() {
    if (hasPack) cost = packCost / packSize;
  }

  /// Valor que entra no orçamento quando a peça sai do estoque.
  double get budgetPrice => price > 0 ? price : cost;

  /// Valor parado no estoque (custo × quantidade).
  double get stockValue => cost * (qty < 0 ? 0 : qty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'partNumber': partNumber,
        'fits': fits,
        'qty': qty,
        'unit': unit,
        'cost': cost,
        if (hasPack) ...{
          'packName': packName,
          'packSize': packSize,
          'packCost': packCost,
        },
        'price': price,
        'corridor': corridor,
        'shelf': shelf,
        'slot': slot,
        'location': location,
        'notes': notes,
        'photo': photo,
        if (claimId.isNotEmpty) 'claim': claimId,
        if (sku.isNotEmpty) 'sku': sku,
        if (mfrBrand.isNotEmpty) 'mfrBrand': mfrBrand,
        if (mfrCode.isNotEmpty) 'mfrCode': mfrCode,
        if (condition.isNotEmpty) 'condition': condition,
        if (applications.isNotEmpty)
          'apps': applications.map((a) => a.toJson()).toList(),
      };

  factory StockItem.fromJson(Map<String, dynamic> j) {
    String s(Object? v) => v == null ? '' : v.toString();
    double d(Object? v, [double def = 0]) =>
        v is num ? v.toDouble() : double.tryParse(s(v)) ?? def;
    return StockItem(
      id: s(j['id']).isEmpty ? null : s(j['id']),
      kind: StockKind.values
              .where((e) => e.name == j['kind'])
              .firstOrNull ??
          StockKind.peca,
      name: s(j['name']),
      partNumber: s(j['partNumber']),
      fits: s(j['fits']),
      qty: d(j['qty'], 1),
      unit: s(j['unit']).isEmpty ? 'un' : s(j['unit']),
      cost: d(j['cost']),
      packName: s(j['packName']).isEmpty ? 'lata' : s(j['packName']),
      packSize: d(j['packSize']),
      packCost: d(j['packCost']),
      price: d(j['price']),
      corridor: s(j['corridor']),
      shelf: s(j['shelf']),
      slot: s(j['slot']),
      location: s(j['location']),
      notes: s(j['notes']),
      photo: s(j['photo']),
      claimId: s(j['claim']),
      sku: s(j['sku']),
      mfrBrand: s(j['mfrBrand']),
      mfrCode: s(j['mfrCode']),
      condition: s(j['condition']),
      applications: [
        for (final a in (j['apps'] as List? ?? const []))
          if (a is Map) VehicleFit.fromJson(Map<String, dynamic>.from(a))
      ],
    );
  }
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'ê': 'e', 'è': 'e',
  'í': 'i', 'î': 'i',
  'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ü': 'u',
  'ç': 'c',
};

/// Palavras que não ajudam a achar a peça.
const _stop = {'de', 'da', 'do', 'das', 'dos', 'e', 'para', 'com', 'a', 'o'};

String _norm(String t) {
  final low = t.toLowerCase();
  final b = StringBuffer();
  for (final ch in low.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _words(String t) => _norm(t)
    .split(' ')
    .where((w) => w.isNotEmpty && !_stop.contains(w))
    .map((w) => switch (w) {
          'esq' || 'le' => 'esquerdo',
          'dir' || 'ld' => 'direito',
          'esquerda' => 'esquerdo',
          'direita' => 'direito',
          'dianteira' => 'dianteiro',
          'traseira' => 'traseiro',
          _ => w,
        })
    .toSet();

/// A peça do estoque serve para este item do orçamento?
/// Mesmo código de peça, ou todas as palavras de um estão no outro
/// ("Farol esquerdo" ↔ "Farol esquerdo Gol G5"), sem trocar lado.
bool stockMatchesItem(StockItem s, BudgetItem it) {
  if (s.kind != StockKind.peca) return false;
  final pn = _norm(s.partNumber).replaceAll(' ', '');
  if (pn.isNotEmpty && pn == _norm(it.partNumber).replaceAll(' ', '')) {
    return true;
  }
  final a = _words(s.name);
  final b = _words(it.description);
  if (a.isEmpty || b.isEmpty) return false;
  return b.every(a.contains) || a.every(b.contains);
}

/// Peças do estoque que servem para o item (com saldo, ou a já escolhida).
List<StockItem> stockFor(List<StockItem> stock, BudgetItem it,
    [Vehicle? vehicle]) {
  if (it.op != ItemOp.troca) return const [];
  return stock
      .where((s) =>
          s.id == it.stockId ||
          (s.qty > 0 &&
              stockMatchesItem(s, it) &&
              (vehicle == null || fitsVehicle(s, vehicle))))
      .toList()
    ..sort((a, b) => b.qty.compareTo(a.qty));
}

String _plural(String w) => switch (w) {
      'galão' => 'galões',
      'un' => 'un',
      _ => w.endsWith('s') ? w : '${w}s',
    };

/// Lê o conteúdo da embalagem no nome (ex.: "Thinner 900ml" → 900 ml,
/// "Verniz 3,6 L" → 3,6 litro).
(double, String)? packFromName(String name) {
  final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(ml|l|lt|litros?|g|kg)\b', caseSensitive: false)
      .firstMatch(name);
  if (m == null) return null;
  final v = double.tryParse(m[1]!.replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  final u = m[2]!.toLowerCase();
  return switch (u) {
    'ml' => (v, 'ml'),
    'g' => (v, 'g'),
    'kg' => (v, 'kg'),
    _ => (v, 'litro'),
  };
}


/// Pedaços de folha de lixa: a folha é cortada em 4.
const sheetPieces = [
  (0.25, '1/4 de folha', 'um pedaço'),
  (0.5, '2/4 no taco', 'meia folha: dois pedaços no taco'),
  (1.0, 'Folha inteira', 'sem cortar'),
];

/// Quantidade com a unidade. Folha aparece em quartos ("1 e 1/4 folha").
String qtyText(double q, String unit) {
  if (unit == 'folha') {
    final quarters = (q * 4).round();
    if ((q * 4 - quarters).abs() < 1e-6) {
      final neg = quarters < 0;
      final a = quarters.abs();
      final whole = a ~/ 4, rest = a % 4;
      final frac = switch (rest) { 1 => '1/4', 2 => '1/2', 3 => '3/4', _ => '' };
      final txt = whole == 0
          ? (frac.isEmpty ? '0 folha' : (rest == 2 ? '1/2 folha' : '$frac de folha'))
          : (frac.isEmpty
              ? '$whole ${whole == 1 ? 'folha' : 'folhas'}'
              : '$whole e $frac ${whole == 1 ? 'folha' : 'folhas'}');
      return neg ? '-$txt' : txt;
    }
  }
  if (unit == 'disco') return '${num2(q)} ${q == 1 ? 'disco' : 'discos'}';
  return '${num2(q)} $unit';
}


// ------------------------------------------------- aplicação veicular

/// Carro em que a peça serve.
class VehicleFit {
  String make; // montadora
  String model;
  int? yearFrom;
  int? yearTo;
  String engine; // motorização (1.0, 1.6 16V, 2.0 TSI…)
  String version; // versão (Trend, Comfortline, LTZ…)

  VehicleFit({
    this.make = '',
    this.model = '',
    this.yearFrom,
    this.yearTo,
    this.engine = '',
    this.version = '',
  });

  String get years {
    if (yearFrom == null && yearTo == null) return '';
    if (yearFrom != null && yearTo != null) {
      return yearFrom == yearTo ? '$yearFrom' : '$yearFrom–$yearTo';
    }
    return yearFrom != null ? 'de $yearFrom em diante' : 'até $yearTo';
  }

  String get label => [make, model, engine, version, years]
      .where((e) => e.trim().isNotEmpty)
      .join(' ');

  bool get isEmpty => make.trim().isEmpty && model.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        if (yearFrom != null) 'from': yearFrom,
        if (yearTo != null) 'to': yearTo,
        if (engine.isNotEmpty) 'engine': engine,
        if (version.isNotEmpty) 'version': version,
      };

  factory VehicleFit.fromJson(Map<String, dynamic> j) => VehicleFit(
        make: '${j['make'] ?? ''}',
        model: '${j['model'] ?? ''}',
        yearFrom: (j['from'] as num?)?.toInt(),
        yearTo: (j['to'] as num?)?.toInt(),
        engine: '${j['engine'] ?? ''}',
        version: '${j['version'] ?? ''}',
      );
}

/// Montadoras mais comuns (para escolher em vez de digitar).
const commonMakes = [
  'Chevrolet', 'Fiat', 'Ford', 'Honda', 'Hyundai', 'Jeep', 'Nissan',
  'Peugeot', 'Citroën', 'Renault', 'Toyota', 'Volkswagen', 'Mitsubishi',
  'Kia', 'BMW', 'Mercedes-Benz', 'Audi', 'Caoa Chery', 'BYD', 'GWM',
];

const _makeAliases = {
  'vw': 'volkswagen', 'volks': 'volkswagen', 'gm': 'chevrolet',
  'chevy': 'chevrolet', 'mercedes': 'mercedes-benz', 'mb': 'mercedes-benz',
  'citroen': 'citroën', 'chery': 'caoa chery', 'great wall': 'gwm',
};

/// Montadora sem variação de escrita ("VW" = "Volkswagen").
String normMake(String m) {
  final t = m.trim().toLowerCase();
  return _makeAliases[t] ?? t;
}

/// Nome oficial da montadora quando é uma das comuns.
String canonicalMake(String m) {
  final n = normMake(m);
  for (final c in commonMakes) {
    if (c.toLowerCase() == n) return c;
  }
  return m.trim();
}

/// Código sem espaço, ponto ou traço, em maiúsculas ("5u0-941.005" = "5U0941005").
String normCode(String c) => c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String _normModel(String m) => _norm(m).replaceAll(' ', '');

bool _yearsOverlap(VehicleFit a, VehicleFit b) {
  final a1 = a.yearFrom ?? 0, a2 = a.yearTo ?? 9999;
  final b1 = b.yearFrom ?? 0, b2 = b.yearTo ?? 9999;
  return a1 <= b2 && b1 <= a2;
}

bool _sameCar(VehicleFit a, VehicleFit b) {
  if (normMake(a.make) != normMake(b.make)) return false;
  final ma = _normModel(a.model), mb = _normModel(b.model);
  if (ma.isEmpty || mb.isEmpty) return false;
  return (ma == mb || ma.startsWith(mb) || mb.startsWith(ma)) && _yearsOverlap(a, b);
}

/// A peça serve neste carro? (sem aplicação cadastrada: não dá para saber → serve)
bool fitsVehicle(StockItem s, Vehicle v) {
  if (s.applications.isEmpty || v.model.trim().isEmpty) return true;
  final year = int.tryParse(RegExp(r'\d{4}').firstMatch(v.year)?[0] ?? '');
  final cm = _normModel(v.model);
  for (final a in s.applications) {
    if (v.brand.trim().isNotEmpty &&
        a.make.trim().isNotEmpty &&
        normMake(a.make) != normMake(v.brand)) {
      continue;
    }
    final am = _normModel(a.model);
    if (am.isEmpty || !(cm.contains(am) || am.contains(cm))) continue;
    if (year != null &&
        ((a.yearFrom != null && year < a.yearFrom!) ||
            (a.yearTo != null && year > a.yearTo!))) {
      continue;
    }
    return true;
  }
  return false;
}

/// Possíveis cadastros repetidos da mesma peça, com o motivo.
List<(StockItem, String)> findDuplicates(List<StockItem> stock, StockItem s) {
  if (s.kind != StockKind.peca) return const [];
  final out = <(StockItem, String)>[];
  final oem = normCode(s.partNumber);
  final mfr = normCode(s.mfrCode);
  final words = _words(s.name);
  for (final o in stock) {
    if (o.id == s.id || o.kind != StockKind.peca) continue;
    if (oem.isNotEmpty && oem == normCode(o.partNumber)) {
      out.add((o, 'mesmo código OEM'));
    } else if (mfr.isNotEmpty &&
        mfr == normCode(o.mfrCode) &&
        normMake(s.mfrBrand) == normMake(o.mfrBrand)) {
      out.add((o, 'mesmo código do fabricante'));
    } else if (words.isNotEmpty &&
        _words(o.name).length == words.length &&
        _words(o.name).every(words.contains) &&
        (s.applications.isEmpty ||
            o.applications.isEmpty ||
            s.applications.any((a) => o.applications.any((b) => _sameCar(a, b))))) {
      out.add((o, 'mesmo nome e mesmo carro'));
    }
  }
  return out;
}

/// Próximo código interno: P-0001, P-0002…
String nextSku(List<StockItem> stock) {
  var max = 0;
  for (final s in stock) {
    final m = RegExp(r'^P-(\d+)$').firstMatch(s.sku);
    if (m != null) max = [max, int.parse(m[1]!)].reduce((a, b) => a > b ? a : b);
  }
  return 'P-${(max + 1).toString().padLeft(4, '0')}';
}
