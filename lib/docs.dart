// Arquivo de documentos: toda nota de compra e todo orçamento de seguradora
// lido pelo app fica guardado (o arquivo e o que foi lido) e ligado ao que
// gerou: entradas no estoque, lançamento no Financeiro, fornecedor e
// orçamento.

import 'models.dart';
import 'receipt_parser.dart';

enum DocKind {
  notaCompra('Nota de compra'),
  orcamentoSeguradora('Orçamento da seguradora');

  const DocKind(this.label);
  final String label;
}

enum DocSource {
  foto('Foto'),
  xml('XML da NF-e'),
  pdf('PDF'),
  manual('Sem arquivo');

  const DocSource(this.label);
  final String label;
}

/// Um item lido do documento.
class DocItem {
  DocItem({
    this.description = '',
    this.code = '',
    this.qty = 1,
    this.unit = '',
    this.unitPrice = 0,
    this.total = 0,
    this.stockId = '',
  });

  String description;
  String code;
  double qty;
  String unit;
  double unitPrice;
  double total;

  /// Item do estoque que recebeu esta linha ('' = não entrou no estoque).
  String stockId;

  Map<String, dynamic> toJson() => {
        'd': description,
        if (code.isNotEmpty) 'c': code,
        'q': qty,
        if (unit.isNotEmpty) 'u': unit,
        'p': unitPrice,
        't': total,
        if (stockId.isNotEmpty) 's': stockId,
      };

  factory DocItem.fromJson(Map<String, dynamic> j) {
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    String s(Object? v) => v == null ? '' : '$v';
    return DocItem(
      description: s(j['d']),
      code: s(j['c']),
      qty: d(j['q']),
      unit: s(j['u']),
      unitPrice: d(j['p']),
      total: d(j['t']),
      stockId: s(j['s']),
    );
  }
}

class StoredDoc {
  StoredDoc({
    String? id,
    this.kind = DocKind.notaCompra,
    this.source = DocSource.manual,
    this.file = '',
    DateTime? date,
    DateTime? createdAt,
    this.party = '',
    this.number = '',
    this.total = 0,
    this.payment = '',
    List<DocItem>? items,
    this.financeId = '',
    this.claimId = '',
  })  : id = id ?? newId(),
        date = date ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        items = items ?? [];

  String id;
  DocKind kind;
  DocSource source;

  /// Arquivo guardado na pasta de fotos (imagem, .xml ou .pdf).
  String file;

  /// Data do documento (emissão) e quando foi guardado no app.
  DateTime date;
  DateTime createdAt;

  /// Fornecedor (nota) ou seguradora (orçamento).
  String party;

  /// Nº da nota / reserva / sinistro.
  String number;
  double total;
  String payment;
  List<DocItem> items;

  /// Lançamento do Financeiro e orçamento ligados a este documento.
  String financeId;
  String claimId;

  bool get inStock => items.any((i) => i.stockId.isNotEmpty);
  bool get isImage => source == DocSource.foto;

  String get title => party.isEmpty ? kind.label : party;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'source': source.name,
        if (file.isNotEmpty) 'file': file,
        'date': date.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'party': party,
        if (number.isNotEmpty) 'number': number,
        'total': total,
        if (payment.isNotEmpty) 'payment': payment,
        if (items.isNotEmpty) 'items': items.map((e) => e.toJson()).toList(),
        if (financeId.isNotEmpty) 'finance': financeId,
        if (claimId.isNotEmpty) 'claim': claimId,
      };

  factory StoredDoc.fromJson(Map<String, dynamic> j) {
    String s(Object? v) => v == null ? '' : '$v';
    return StoredDoc(
      id: s(j['id']).isEmpty ? null : s(j['id']),
      kind: DocKind.values.where((e) => e.name == j['kind']).firstOrNull ??
          DocKind.notaCompra,
      source: DocSource.values.where((e) => e.name == j['source']).firstOrNull ??
          DocSource.manual,
      file: safeFileName(j['file']),
      date: DateTime.tryParse(s(j['date'])),
      createdAt: DateTime.tryParse(s(j['createdAt'])),
      party: s(j['party']),
      number: s(j['number']),
      total: j['total'] is num ? (j['total'] as num).toDouble() : 0,
      payment: s(j['payment']),
      items: [
        for (final i in (j['items'] is List ? j['items'] as List : const []))
          if (i is Map) DocItem.fromJson(Map<String, dynamic>.from(i))
      ],
      financeId: s(j['finance']),
      claimId: s(j['claim']),
    );
  }

  /// Documento a partir do que foi lido da nota.
  factory StoredDoc.fromReceipt(ReceiptData d,
          {DocSource source = DocSource.foto, String file = ''}) =>
      StoredDoc(
        kind: DocKind.notaCompra,
        source: source,
        file: file,
        date: d.date,
        party: d.supplier,
        number: d.docNumber,
        total: d.total,
        payment: d.payment,
        items: [
          for (final i in d.items)
            DocItem(
              description: i.description,
              code: i.code,
              qty: i.qty,
              unit: i.unit,
              unitPrice: i.unitPrice,
              total: i.total,
            )
        ],
      );

  /// O que foi lido, de volta no formato do leitor (para dar entrada depois).
  ReceiptData toReceipt() => ReceiptData(
        supplier: party,
        date: date,
        total: total,
        items: [
          for (final i in items)
            ReceiptItem(i.description, i.qty, i.unit, i.unitPrice, i.total, code: i.code)
        ],
        category: ExpenseCategory.materiais,
        rawText: '',
        docNumber: number,
        payment: payment,
      );
}

String _n(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A mesma nota já foi guardada? (mesmo fornecedor e número; sem número,
/// mesmo fornecedor, dia e total)
StoredDoc? findSameNote(List<StoredDoc> docs, ReceiptData d) {
  for (final x in docs) {
    if (x.kind != DocKind.notaCompra) continue;
    if (_n(x.party) != _n(d.supplier)) continue;
    if (d.docNumber.isNotEmpty || x.number.isNotEmpty) {
      if (_n(x.number) == _n(d.docNumber)) return x;
      continue;
    }
    final sameDay = d.date != null &&
        x.date.year == d.date!.year &&
        x.date.month == d.date!.month &&
        x.date.day == d.date!.day;
    if (sameDay && d.total > 0 && (x.total - d.total).abs() < 0.01) return x;
  }
  return null;
}
