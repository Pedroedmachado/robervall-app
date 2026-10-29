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
  }) : id = id ?? newId();

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

  /// "900 ml (1 lata)" ou "3 un".
  String get qtyLabel =>
      '${num2(qty)} $unit${hasPack ? ' (${num2(packs)} ${packs < 2 ? packName : _plural(packName)})' : ''}';

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
List<StockItem> stockFor(List<StockItem> stock, BudgetItem it) {
  if (it.op != ItemOp.troca) return const [];
  return stock
      .where((s) =>
          s.id == it.stockId || (s.qty > 0 && stockMatchesItem(s, it)))
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
