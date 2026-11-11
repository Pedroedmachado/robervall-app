import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/receipt_parser.dart';
import 'package:funilar/stock.dart';
import 'package:funilar/stock_entry.dart';

/// Layouts diferentes de nota/cupom: o leitor acha item, quantidade e preço
/// em todos, sem depender do formato.
void main() {
  void check(ReceiptItem it, String desc, double qty, double unit, double total) {
    expect(it.description.toUpperCase(), startsWith(desc.toUpperCase()));
    expect(it.qty, closeTo(qty, 0.001), reason: it.description);
    expect(it.unitPrice, closeTo(unit, 0.01), reason: it.description);
    expect(it.total, closeTo(total, 0.01), reason: it.description);
  }

  test('cupom fiscal (NFC-e): nº do item, código de barras e "2 UN X 4,99"', () {
    final r = parseReceipt(const [
      'AUTO PECAS BOM PRECO LTDA',
      'CNPJ: 11.222.333/0001-44',
      'CUPOM FISCAL ELETRONICO - NFC-E',
      '# CODIGO DESCRICAO QTD UN VL UNIT VL TOTAL',
      '001 7891000100103 OLEO 5W30 SINTETICO 1L 2 UN X 39,90 79,80',
      '002 7896543210987 FILTRO DE OLEO PSL55 1 UN X 24,50 24,50',
      '003 7890000000017 PALHETA LIMPADOR 2,000 UN X 18,00 36,00',
      'QTD. TOTAL DE ITENS 3',
      'VALOR TOTAL R\$ 140,30',
      'CARTAO DE CREDITO 140,30',
      'CONSUMIDOR NAO IDENTIFICADO',
    ]);
    expect(r.items.length, 3);
    check(r.items[0], 'OLEO 5W30', 2, 39.90, 79.80);
    expect(r.items[0].code, '7891000100103');
    expect(r.items[0].unit, 'UN');
    check(r.items[1], 'FILTRO DE OLEO', 1, 24.50, 24.50);
    check(r.items[2], 'PALHETA', 2, 18, 36);
    expect(r.total, closeTo(140.30, 0.001));
    expect(r.itemsSum, closeTo(r.total, 0.001));
  });

  test('cupom com o item em duas linhas (descrição em cima, conta embaixo)', () {
    final r = parseReceipt(const [
      'MERCADO CENTRAL',
      'ITEM CODIGO DESCRICAO',
      'QTD UN VL UNIT VL TOTAL',
      '001 7891000100103 ESTOPA BRANCA 1KG',
      '2 UN X 12,50 25,00',
      '002 7891234567895 LUVA NITRILICA',
      '1 CX X 35,90 35,90',
      'TOTAL R\$ 60,90',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'ESTOPA BRANCA', 2, 12.5, 25);
    expect(r.items[0].code, '7891000100103');
    check(r.items[1], 'LUVA NITRILICA', 1, 35.9, 35.9);
    expect(r.items[1].unit, 'CX');
  });

  test('preço antes da quantidade, com "x" e "="', () {
    final r = parseReceipt(const [
      'FERRAGENS SAO JOSE',
      'PARAFUSO SEXTAVADO M8 2 x 1,50 = 3,00',
      'ARRUELA LISA 3/8 10,00 x 0,25 = 2,50',
      'TOTAL: 5,50',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'PARAFUSO SEXTAVADO M8', 2, 1.5, 3);
    check(r.items[1], 'ARRUELA LISA', 10, 0.25, 2.5);
  });

  test('coluna de desconto no meio (qtd, preço, desconto, total)', () {
    final r = parseReceipt(const [
      'DISTRIBUIDORA ABRASIVOS',
      'DESCRICAO QTD UN PRECO DESC TOTAL',
      'DISCO DE CORTE 4.1/2 10 UN 5,00 5,00 45,00',
      'LIXA P320 50 FL 1,20 10,00 54,00',
      'TOTAL 99,00',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'DISCO DE CORTE', 10, 4.5, 45);
    check(r.items[1], 'LIXA P320', 50, 1.08, 54); // 10% de desconto
  });

  test('DANFE: colunas de NCM/CFOP e impostos depois do total', () {
    final r = parseReceipt(const [
      'TINTAS EXEMPLO LTDA',
      'DANFE',
      'CODIGO DESCRICAO NCM CST CFOP UN QTD VL.UNIT VL.TOTAL BC.ICMS VL.ICMS IPI ALIQ',
      'VZ-1300 VERNIZ HS 2X1 900ML 32089010 0102 5102 UN 4,0000 89,0000 356,00 356,00 64,08 0,00 18,00',
      'TH-700 THINNER PU 5L 38140000 0102 5102 UN 2,0000 41,0000 82,00 82,00 14,76 0,00 18,00',
      'VALOR TOTAL DOS PRODUTOS 438,00',
      'VALOR TOTAL DA NOTA 438,00',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'VERNIZ HS 2X1 900ML', 4, 89, 356);
    expect(r.items[0].code, 'VZ-1300');
    check(r.items[1], 'THINNER PU 5L', 2, 41, 82);
    expect(r.items[1].code, 'TH-700');
    expect(r.total, 438);
  });

  test('só preço e total ("1,50 4,50" → 3 unidades)', () {
    final r = parseReceipt(const [
      'LOJA DO PINTOR',
      'FITA CREPE 3M 18MM 4,90 14,70',
      'MASCARAMENTO PAPEL 1,50 4,50',
      'TOTAL 19,20',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'FITA CREPE 3M', 3, 4.9, 14.7);
    check(r.items[1], 'MASCARAMENTO PAPEL', 3, 1.5, 4.5);
  });

  test('cupom simples: só o nome e o valor (qtd 1)', () {
    final r = parseReceipt(const [
      'CASA DAS TINTAS',
      'CNPJ 12.345.678/0001-90',
      '05/11/2026 10:22',
      'ESTOPA BRANCA 12,00',
      'LUVA NITRILICA 25,50',
      'TELA DE MASCARAMENTO 8,90',
      'TOTAL 46,40',
      'DINHEIRO 50,00',
      'TROCO 3,60',
    ]);
    expect(r.items.length, 3);
    check(r.items[0], 'ESTOPA BRANCA', 1, 12, 12);
    check(r.items[2], 'TELA DE MASCARAMENTO', 1, 8.9, 8.9);
    expect(r.total, closeTo(46.40, 0.001));
    expect(r.itemsSum, closeTo(46.40, 0.001));
  });

  test('ponto no lugar da vírgula (OCR) e tudo na mesma linha', () {
    final r = parseReceipt(const [
      'COMERCIAL AUTOMOTIVA',
      'THINNER 2750 5 LT 47.50 237.50',
      'PRIMER PU CINZA 3 UN 89.00 267.00',
      'TOTAL 504.50',
    ]);
    expect(r.items.length, 2);
    check(r.items[0], 'THINNER 2750', 5, 47.5, 237.5);
    expect(r.items[0].unit, 'LT');
    check(r.items[1], 'PRIMER PU CINZA', 3, 89, 267);
  });

  test('qualquer layout vira entrada no estoque sem digitar nada', () {
    final r = parseReceipt(const [
      'AUTO PECAS BOM PRECO LTDA',
      '001 7891000100103 OLEO 5W30 SINTETICO 1L 2 UN X 39,90 79,80',
      '002 7896543210987 FILTRO DE OLEO PSL55 1 UN X 24,50 24,50',
      'VALOR TOTAL R\$ 104,30',
    ]);
    final lines = planStockEntry(r, []);
    final created = applyStockEntry(lines);
    expect(created.length, 2);
    expect(created[0].qty, 2);
    expect(created[0].cost, closeTo(39.90, 0.001));
    expect(created.fold(0.0, (a, s) => a + s.stockValue), closeTo(104.30, 0.01));
    expect(created.every((s) => s.kind == StockKind.peca || s.kind == StockKind.material), isTrue);
  });
}
