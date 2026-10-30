/// Caixa (regime de caixa): dinheiro que realmente entrou e saiu, e o que
/// está previsto para entrar e sair. Fica separado de Vendas (competência).
library;

import 'finance.dart' show Period;
import 'models.dart' show newId;

enum CashMethod {
  dinheiro('Dinheiro'),
  pix('Pix'),
  cheque('Cheque'),
  debito('Cartão de débito'),
  credito('Cartão de crédito'),
  boleto('Boleto'),
  transferencia('Transferência'),
  outro('Outro');

  const CashMethod(this.label);
  final String label;
}

/// Categorias de entrada e de saída do caixa.
const cashInCategories = [
  'Recebimento de cliente',
  'Seguradora',
  'Lucro de orçamento',
  'Venda de sucata',
  'Aporte',
  'Outros',
];

const cashOutCategories = [
  'Água',
  'Energia',
  'Aluguel',
  'Internet / telefone',
  'Salários',
  'Fornecedores',
  'Impostos',
  'Manutenção',
  'Outros',
];

/// Chave do lançamento automático do lucro de orçamento concluído.
const cashProfitKey = 'lucro';

class CashEntry {
  String id;
  bool isIn; // true = entrada, false = saída
  DateTime date; // data em que aconteceu (ou data prevista)
  String description;
  double amount; // sempre positivo (o tipo diz se entra ou sai)
  CashMethod method;
  String category;
  bool planned; // previsto (ainda não aconteceu)
  String contact;
  String claimId;
  String autoKey; // vazio = lançado à mão
  String notes;

  CashEntry({
    String? id,
    this.isIn = true,
    DateTime? date,
    this.description = '',
    this.amount = 0,
    this.method = CashMethod.pix,
    this.category = '',
    this.planned = false,
    this.contact = '',
    this.claimId = '',
    this.autoKey = '',
    this.notes = '',
  })  : id = id ?? newId(),
        date = date ?? DateTime.now();

  /// Valor com sinal: entrada soma, saída subtrai.
  double get signed => isIn ? amount : -amount;

  /// Previsto e com a data já passada.
  bool get overdue {
    final n = DateTime.now();
    return planned && date.isBefore(DateTime(n.year, n.month, n.day));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'in': isIn,
        'date': date.toIso8601String(),
        'description': description,
        'amount': amount,
        'method': method.name,
        'category': category,
        if (planned) 'planned': true,
        if (contact.isNotEmpty) 'contact': contact,
        if (claimId.isNotEmpty) 'claim': claimId,
        if (autoKey.isNotEmpty) 'auto': autoKey,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory CashEntry.fromJson(Map<String, dynamic> j) => CashEntry(
        id: '${j['id'] ?? ''}'.isEmpty ? null : '${j['id']}',
        isIn: j['in'] != false,
        date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        description: '${j['description'] ?? ''}',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        method: CashMethod.values
                .where((m) => m.name == j['method'])
                .firstOrNull ??
            CashMethod.outro,
        category: '${j['category'] ?? ''}',
        planned: j['planned'] == true,
        contact: '${j['contact'] ?? ''}',
        claimId: '${j['claim'] ?? ''}',
        autoKey: '${j['auto'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
      );
}

/// Números do caixa num período.
class CashSummary {
  final double entradas; // realizadas
  final double saidas; // realizadas
  final double previstoEntrar; // previstos no período
  final double previstoSair;
  final List<CashEntry> realized; // por data
  final List<CashEntry> planned; // por data
  const CashSummary(this.entradas, this.saidas, this.previstoEntrar,
      this.previstoSair, this.realized, this.planned);

  double get saldo => entradas - saidas;
  double get saldoPrevisto => saldo + previstoEntrar - previstoSair;
}

CashSummary summarizeCash(List<CashEntry> cash, Period p) {
  final realized = cash.where((e) => !e.planned && p.contains(e.date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final planned = cash.where((e) => e.planned && p.contains(e.date)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  double sum(Iterable<CashEntry> l) => l.fold(0.0, (a, e) => a + e.amount);
  return CashSummary(
    sum(realized.where((e) => e.isIn)),
    sum(realized.where((e) => !e.isIn)),
    sum(planned.where((e) => e.isIn)),
    sum(planned.where((e) => !e.isIn)),
    realized,
    planned,
  );
}

/// Previstos dos próximos [days] dias (e os atrasados), para não ser pego
/// de surpresa.
List<CashEntry> upcoming(List<CashEntry> cash, {int days = 30, DateTime? now}) {
  final n = now ?? DateTime.now();
  final limit = DateTime(n.year, n.month, n.day + days + 1);
  return cash.where((e) => e.planned && e.date.isBefore(limit)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

/// Cópias mensais de um previsto (ex.: aluguel nos próximos 12 meses).
List<CashEntry> repeatMonthly(CashEntry e, int months) => [
      for (var i = 1; i < months; i++)
        CashEntry.fromJson(e.toJson())
          ..id = newId()
          ..date = DateTime(e.date.year, e.date.month + i, e.date.day),
    ];
