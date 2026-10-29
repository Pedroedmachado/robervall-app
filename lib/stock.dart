import 'models.dart';

/// Tipo de item do estoque.
enum StockKind {
  peca('Peça'),
  material('Material');

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

  /// Quanto custou cada unidade.
  double cost;

  /// Quanto cobrar no orçamento (0 = usa o custo).
  double price;
  String location;
  String notes;

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
    this.price = 0,
    this.location = '',
    this.notes = '',
    this.photo = '',
  }) : id = id ?? newId();

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
        'price': price,
        'location': location,
        'notes': notes,
        'photo': photo,
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
      price: d(j['price']),
      location: s(j['location']),
      notes: s(j['notes']),
      photo: s(j['photo']),
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
