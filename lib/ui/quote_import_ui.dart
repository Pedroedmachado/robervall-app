import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../calc.dart';
import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../pdf_words.dart';
import '../quote_import.dart';
import '../store.dart';
import '../theme.dart';
import 'claims_page.dart' show openClaim;
import 'widgets.dart';

/// Sinistros › Importar PDF: lê o orçamento da seguradora (Cilia…) e cria um
/// orçamento editável no app.
Future<void> importQuoteFromPdf(BuildContext context) async {
  if (!gate.can(Perm.sinistroEditar)) {
    toast(context,
        gate.readOnly ? 'Somente consulta (licença).' : 'Seu usuário não cria sinistros.');
    return;
  }
  XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Orçamento em PDF',
        extensions: ['pdf'],
        mimeTypes: ['application/pdf'],
        uniformTypeIdentifiers: ['com.adobe.pdf'],
      ),
    ]);
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível abrir o seletor de arquivos: $e');
    return;
  }
  if (file == null || !context.mounted) return;
  final Uint8List bytes;
  ImportedQuote q;
  try {
    bytes = await file.readAsBytes();
    final words = extractPdfWords(bytes);
    if (words.isEmpty) {
      if (context.mounted) {
        toast(context,
            'Esse PDF não tem texto (parece escaneado/foto). Use o PDF original enviado pela seguradora.');
      }
      return;
    }
    q = parseInsurerQuote(words);
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível ler o PDF: $e');
    return;
  }
  if (!context.mounted) return;
  await reviewImportedQuote(context, q, pdf: bytes);
}

/// Tela de conferência do que foi lido; "Criar orçamento" grava e abre.
Future<void> reviewImportedQuote(BuildContext context, ImportedQuote q,
    {Uint8List? pdf}) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ReviewPage(quote: q),
  ));
  if (ok != true || !context.mounted) return;
  final store = StoreScope.read(context);
  final same = store.sameInsurerQuote(q.claim);
  if (same != null) {
    final again = await confirm(
        context,
        'Este sinistro já foi importado',
        'O orçamento ${same.number} já tem o sinistro ${same.claimNumber}${same.insurerName.isEmpty ? '' : ' (${same.insurerName})'}. Importar de novo cria outro orçamento.',
        ok: 'Importar de novo');
    if (!context.mounted) return;
    if (!again) {
      await openClaim(context, same);
      return;
    }
  }
  final c = await store.addImportedClaim(q.claim, pdf: pdf, system: q.system);
  if (!context.mounted) return;
  toast(context,
      'Orçamento ${c.number} criado. O PDF ficou guardado em Documentos e os cadastros foram atualizados.');
  await openClaim(context, c);
}

/// Abre o PDF original guardado junto do orçamento.
Future<void> openSourcePdf(BuildContext context, AppStore store, Claim c) async {
  try {
    final f = store.sourcePdfFile(c);
    if (!await f.exists()) {
      if (context.mounted) toast(context, 'PDF original não encontrado neste aparelho.');
      return;
    }
    final bytes = await f.readAsBytes();
    await Printing.layoutPdf(
        onLayout: (_) async => bytes, name: 'Original ${c.claimNumber.isEmpty ? c.number : c.claimNumber}');
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível abrir o PDF: $e');
  }
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({required this.quote});
  final ImportedQuote quote;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = quote;
    final c = q.claim;
    final s = store.settings.forClaim(c);
    final totals = computeTotals(c, s);
    final v = c.vehicle;
    final diff = q.pdfTotal > 0 ? (totals.total - q.pdfTotal).abs() : 0.0;

    String ops(BudgetItem it) {
      final p = <String>[];
      if (it.op == ItemOp.troca) p.add('T');
      if (it.op == ItemOp.servico) p.add('S');
      if (it.op == ItemOp.reparo) {
        if (it.removeInstall) p.add('R&I');
        if (!it.removeInstall || it.alsoRepair) p.add('R');
      }
      if (it.laborHours > 0) p.add('${num2(it.laborHours)} h');
      if (it.paintHours > 0) p.add('P ${num2(it.paintHours)} h');
      return p.join(' · ');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conferir orçamento importado'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check),
              label: const Text('Criar orçamento'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: q.recognized ? null : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(q.recognized ? Icons.picture_as_pdf : Icons.warning_amber,
                        color: q.recognized ? brandSeed : Colors.orange.shade800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(q.recognized
                          ? 'PDF lido (${q.system}). Confira abaixo: depois de criar, tudo pode ser alterado normalmente no app.'
                          : 'Não reconheci o formato deste PDF.'),
                    ),
                  ]),
                ),
              ),
              for (final w in q.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('⚠ $w', style: TextStyle(color: Colors.orange.shade900)),
                ),
              SectionCard(title: 'Veículo', icon: Icons.directions_car_outlined, children: [
                _Kv('Veículo', [v.brand, v.model, v.year].where((e) => e.isNotEmpty).join(' ')),
                _Kv('Placa', v.plate),
                _Kv('Cor', v.color),
                _Kv('Chassi', v.chassis),
                if (v.km.isNotEmpty) _Kv('Quilometragem', v.km),
                if (v.fipeValue > 0)
                  _Kv('Valor FIPE${v.fipeCode.isEmpty ? '' : ' (${v.fipeCode})'}',
                      money(v.fipeValue)),
              ]),
              SectionCard(title: 'Seguro e cliente', icon: Icons.shield_outlined, children: [
                _Kv('Atendimento', c.type.label),
                if (c.insurerName.isNotEmpty) _Kv('Seguradora', c.insurerName),
                if (c.claimNumber.isNotEmpty) _Kv('Sinistro', c.claimNumber),
                if (c.regulatorName.isNotEmpty) _Kv('Regulador', c.regulatorName),
                _Kv(c.type == ClaimType.terceiro ? 'Terceiro' : 'Cliente', c.customerName),
                if (c.customerDoc.isNotEmpty) _Kv('CPF/CNPJ', c.customerDoc),
                if (c.customerPhone.isNotEmpty) _Kv('Telefone', c.customerPhone),
              ]),
              SectionCard(title: 'Valores da hora (do PDF)', icon: Icons.schedule, children: [
                _Kv('Mão de obra',
                    c.laborRate > 0 ? '${money(c.laborRate)}/h' : 'os da oficina'),
                _Kv('Pintura (com material)',
                    c.paintRate > 0 ? '${money(c.paintRate)}/h' : 'os da oficina'),
                if (q.partsDiscountPct > 0)
                  _Kv('Desconto nas peças', '${num2(q.partsDiscountPct)}%'),
              ]),
              SectionCard(
                title: 'Itens (${c.items.length})',
                icon: Icons.list_alt,
                children: [
                  if (c.items.isEmpty) const Text('Nenhum item encontrado.'),
                  for (final it in c.items)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(it.description),
                      subtitle: Text([
                        ops(it),
                        if (it.partNumber.isNotEmpty) 'Cód. ${it.partNumber}',
                        if (it.note.isNotEmpty) it.note,
                      ].where((e) => e.isNotEmpty).join(' · ')),
                      trailing: Text(money(itemValues(it, s).total)),
                    ),
                ],
              ),
              SectionCard(title: 'Total', icon: Icons.calculate_outlined, children: [
                if (q.pdfTotal > 0) _Kv('Total no PDF', money(q.pdfTotal)),
                _Kv('Total no app', money(totals.total), bold: true),
                if (q.pdfTotal > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      diff < 0.05
                          ? '✓ Bate com o PDF.'
                          : 'Diferença de ${money(diff)} — confira os itens depois de criar.',
                      style: TextStyle(
                          color: diff < 0.05 ? Colors.green.shade700 : Colors.orange.shade900,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('import-criar'),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.check),
                label: const Text('Criar orçamento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rótulo e valor; valor comprido quebra linha em vez de estourar a tela.
class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v, {this.bold = false});
  final String k;
  final String v;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(k, style: style)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(v.isEmpty ? '—' : v, style: style, textAlign: TextAlign.end)),
      ]),
    );
  }
}
