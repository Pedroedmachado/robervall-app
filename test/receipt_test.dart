import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/models.dart';
import 'package:funilar/receipt_parser.dart';

void main() {
  // Nota real da Art Color Tintas (como o OCR devolve, linha a linha).
  const artColor = [
    'ART COLOR TINTAS',
    'AV DO CURSINO, 1916',
    'FONE: 001150738518',
    '-----------------------------------------',
    'RESERVA 0819365',
    '22/09/2026-17:19   VEND: 00010-ALISSON SA',
    '-----------------------------------------',
    '000000838 - ABEL STOPCAR',
    'ABEL NOVA COSKI',
    '22.832.525/0001-26',
    '- ENDERECO DE FATURA ---------',
    'R DIVINO DAS LARANJEIRAS, 224',
    'VL STO ESTEFANO - SAO PAULO',
    'SP - 04154-050',
    'FONE : 001150717931',
    'QTDE UNID   PRC UNIT   TOTAL',
    'VERNIZ A.SOLIDOS HS-2X1 13000 C/CAT.SKY',
    '4,00 QUART   89,00   356,00',
    'ACELERADOR SECAGEM RRA- 1LT SIKKENS',
    '1,00 LITRO   53,90   53,90',
    '-----------------------------------------',
    'TOTAL :   409,90',
    'A vista',
    'TOTAL DE DEBITOS : R\$ 40.126,15',
    'DOCUMENTO SEM VALOR FISCAL !',
  ];

  test('lê a nota da Art Color Tintas', () {
    final r = parseReceipt(artColor);
    expect(r.supplier, 'Art Color Tintas');
    expect(r.date, DateTime(2026, 9, 22));
    expect(r.total, closeTo(409.90, 0.001)); // não pega o "total de débitos"
    expect(r.items.length, 2);
    expect(r.items[0].qty, 4);
    expect(r.items[0].unitPrice, 89);
    expect(r.items[0].total, 356);
    expect(r.items[0].description.toLowerCase(), startsWith('verniz'));
    expect(r.items[1].total, closeTo(53.90, 0.001));
    expect(r.items[1].description.toLowerCase(), startsWith('acelerador'));
    expect(r.category, ExpenseCategory.materiais);
    final e = r.toEntry();
    expect(e.amount, closeTo(409.90, 0.001));
    expect(e.contact, 'Art Color Tintas');
    expect(e.notes, contains('356,00'));
    // nº da nota, pagamento e resumo automático
    expect(r.docNumber, 'Reserva 0819365');
    expect(r.payment, 'À vista');
    expect(e.invoiceNumber, 'Reserva 0819365');
    expect(e.paymentMethod, 'À vista');
    expect(e.description, startsWith('Art Color Tintas · Verniz'));
    expect(e.notes, startsWith('Nota: Reserva 0819365 · 22/09/2026 · À vista'));
    expect(e.notes, contains('Total: '));
    // ida e volta no JSON
    final back = FinanceEntry.fromJson(e.toJson());
    expect(back.invoiceNumber, 'Reserva 0819365');
    expect(back.paymentMethod, 'À vista');
  });

  test('anexar nota num lançamento existente mantém o que não foi lido', () {
    final e = FinanceEntry(description: 'x', amount: 10, invoiceNumber: '55');
    parseReceipt(['LOJA QUALQUER', 'sem números úteis']).applyTo(e);
    expect(e.amount, 10);
    expect(e.invoiceNumber, '55');
  });

  test('aguenta erros comuns do OCR (O no lugar de 0, colunas separadas)', () {
    final pieces = [
      const OcrPiece('ART COLOR TINTAS', 10, 10, 200, 30),
      const OcrPiece('22/09/2O26-17:19', 10, 40, 150, 60),
      const OcrPiece('VERNIZ A.SOLIDOS HS-2X1', 10, 100, 300, 120),
      // colunas da mesma linha vêm separadas e fora de ordem
      const OcrPiece('356,OO', 250, 131, 300, 149),
      const OcrPiece('4,00 QUART', 10, 130, 90, 150),
      const OcrPiece('89,00', 150, 132, 200, 151),
      const OcrPiece('TOTAL :', 120, 200, 180, 220),
      const OcrPiece('356,00', 250, 201, 300, 221),
    ];
    final rows = rowsFromPieces(pieces);
    expect(rows[3], '4,00 QUART   89,00   356,OO');
    final r = parseReceipt(rows);
    expect(r.date, DateTime(2026, 9, 22));
    expect(r.total, 356);
    expect(r.items.single.total, 356);
  });

  test('cupom de autopeças com "VALOR A PAGAR" vira fornecedor', () {
    final r = parseReceipt([
      'AUTO PECAS CENTRAL LTDA',
      'CNPJ 12.345.678/0001-90',
      '05/10/26 10:22',
      'FAROL ESQ GOL G5   1 UN   300,00   300,00',
      'PARA-CHOQUE DIANT   1 UN   250,00   250,00',
      'SUBTOTAL   550,00',
      'DESCONTO   50,00',
      'VALOR A PAGAR R\$   500,00',
    ]);
    expect(r.supplier, 'Auto Pecas Central Ltda');
    expect(r.date, DateTime(2026, 10, 5));
    expect(r.total, 500);
    expect(r.items.length, 2);
    expect(r.category, ExpenseCategory.fornecedor);
  });
}
