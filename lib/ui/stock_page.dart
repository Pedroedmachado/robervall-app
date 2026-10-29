import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models.dart';
import '../modules.dart';
import '../stock.dart';
import '../theme.dart';
import 'access.dart';
import 'widgets.dart';

/// Aba Estoque: peças e materiais guardados na oficina, com foto.
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String _q = '';
  StockKind? _kind;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final q = _q.toLowerCase();
    final list = store.stock
        .where((e) =>
            (_kind == null || e.kind == _kind) &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.partNumber.toLowerCase().contains(q) ||
                e.fits.toLowerCase().contains(q) ||
                e.address.toLowerCase().contains(q)))
        .toList();
    final value = store.stock.fold(0.0, (a, e) => a + e.stockValue);

    return Scaffold(
      appBar: AppBar(title: const Text('Estoque')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (!await authorize(context, Perm.estoqueEditar,
              reason: 'Só o gestor/almoxarife mexe no estoque.')) {
            return;
          }
          if (!context.mounted) return;
          final s = await editStockItem(
              context, StockItem(kind: _kind ?? StockKind.peca));
          if (s != null) store.upsertStock(s);
        },
        icon: const Icon(Icons.add),
        label: const Text('Adicionar'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nome, código, carro ou local',
              ),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              ChoiceChip(
                label: const Text('Tudo'),
                selected: _kind == null,
                onSelected: (_) => setState(() => _kind = null),
              ),
              for (final k in StockKind.values)
                ChoiceChip(
                  label: Text(switch (k) {
                    StockKind.peca => 'Peças',
                    StockKind.material => 'Insumos',
                    StockKind.cliente => 'De clientes',
                  }),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                    '${store.stock.length} ${store.stock.length == 1 ? 'item' : 'itens'} · valor em estoque ${money(value)}',
                    style: t.textTheme.bodySmall),
              ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.warehouse_outlined,
                    text:
                        'Cadastre as peças e os materiais que você tem guardados. Quando um orçamento precisar trocar uma peça que está aqui, o app avisa.')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final s = list[i];
                      final used = store.claimsUsingStock(s);
                      return ListTile(
                        key: ValueKey('stock-${s.id}'),
                        leading: StockThumb(item: s, size: 52),
                        title: Text(s.name.isEmpty ? '(sem nome)' : s.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            s.kind.label,
                            if (s.partNumber.isNotEmpty) s.partNumber,
                            if (s.fits.isNotEmpty) s.fits,
                            if (s.kind == StockKind.cliente)
                              'carro ${store.claimById(s.claimId)?.number ?? '—'}${store.claimById(s.claimId)?.vehicle.plate.isNotEmpty == true ? ' · ${store.claimById(s.claimId)!.vehicle.plate}' : ''}',
                            if (s.address.isNotEmpty) '📍 ${s.address}',
                            if (used.isNotEmpty)
                              'no orçamento ${used.map((c) => c.number).join(', ')}',
                          ].join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(s.qtyLabel,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: s.qty <= 0
                                        ? Colors.red.shade700
                                        : null)),
                            if (s.kind == StockKind.material && s.cost > 0)
                              Text(
                                  s.hasPack
                                      ? '${money(s.packCost)}/${s.packName}'
                                      : '${unitMoney(s.cost)}/${s.unit}',
                                  style: t.textTheme.bodySmall)
                            else if (s.budgetPrice > 0)
                              Text(money(s.budgetPrice),
                                  style: t.textTheme.bodySmall),
                          ],
                        ),
                        onTap: () async {
                          if (!await authorize(context, Perm.estoqueEditar,
                              reason: 'Só o gestor/almoxarife mexe no estoque.')) {
                            return;
                          }
                          if (!context.mounted) return;
                          final r = await editStockItem(
                              context, StockItem.fromJson(s.toJson()),
                              canDelete: true);
                          if (r == null) return;
                          if (r.id == '__delete__') {
                            await store.removeStock(s);
                            if (context.mounted) {
                              showUndo(context, 'Item do estoque excluído',
                                  () => store.upsertStock(s));
                            }
                            return;
                          }
                          final idx = store.stock.indexOf(s);
                          if (idx >= 0) store.stock[idx] = r;
                          store.upsertStock(store.stock[idx]);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura da foto de um item do estoque (ou ícone).
class StockThumb extends StatelessWidget {
  const StockThumb({super.key, required this.item, this.size = 48});
  final StockItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final t = Theme.of(context);
    final icon = Icon(
        item.kind == StockKind.peca
            ? Icons.settings_outlined
            : Icons.format_color_fill_outlined,
        color: t.colorScheme.onSecondaryContainer);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: t.colorScheme.secondaryContainer,
        child: item.photo.isEmpty
            ? icon
            : Image.file(File('${store.photosDir.path}/${item.photo}'),
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => icon),
      ),
    );
  }
}

Future<Uint8List?> _pickPhoto(BuildContext context) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  ImageSource? source = ImageSource.gallery;
  if (mobile) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Tirar foto'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Escolher da galeria'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
  }
  if (source == null) return null;
  try {
    final f = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    return f == null ? null : await f.readAsBytes();
  } catch (e) {
    if (context.mounted) toast(context, 'Não foi possível abrir a foto: $e');
    return null;
  }
}

/// Cadastro de peça/material do estoque. Devolve o item editado; com
/// [canDelete], um item com id "__delete__" quando a pessoa exclui.
Future<StockItem?> editStockItem(BuildContext context, StockItem s,
    {bool canDelete = false}) {
  final store = StoreScope.read(context);
  return showFormDialog<StockItem>(
    context: context,
    title: s.name.isEmpty ? 'Novo no estoque' : 'Editar estoque',
    onSave: () {
      if (s.name.trim().isEmpty) {
        toast(context, 'Informe o nome.');
        return null;
      }
      s.name = s.name.trim();
      if (s.kind == StockKind.material && s.hasPack) {
        s.syncPackCost();
      }
      if (s.kind != StockKind.material) {
        s.packSize = 0;
        s.unit = 'un';
      }
      return s;
    },
    body: (ctx, setS) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<StockKind>(
          segments: const [
            ButtonSegment(
                value: StockKind.peca,
                label: Text('Peça'),
                icon: Icon(Icons.settings_outlined)),
            ButtonSegment(
                value: StockKind.material,
                label: Text('Insumo'),
                icon: Icon(Icons.format_color_fill_outlined)),
            ButtonSegment(
                value: StockKind.cliente,
                label: Text('Do cliente'),
                icon: Icon(Icons.person_pin_outlined)),
          ],
          selected: {s.kind},
          onSelectionChanged: (sel) => setS(() {
            s.kind = sel.first;
            if (s.kind != StockKind.material) s.unit = 'un';
          }),
        ),
        const SizedBox(height: 12),
        Row(children: [
          StockThumb(item: s, size: 72),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final bytes = await _pickPhoto(ctx);
                  if (bytes == null) return;
                  final name = await store.saveStockPhoto(s, bytes);
                  setS(() => s.photo = name);
                },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(s.photo.isEmpty ? 'Adicionar foto' : 'Trocar foto'),
              ),
              if (s.photo.isNotEmpty)
                TextButton(
                  onPressed: () => setS(() => s.photo = ''),
                  child: const Text('Tirar foto'),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        BoundField(
          label: switch (s.kind) {
            StockKind.peca => 'Peça (ex.: Farol esquerdo)',
            StockKind.material => 'Insumo (ex.: Lixa P320, Verniz HS 2x1)',
            StockKind.cliente => 'Peça do cliente (ex.: Para-choque retirado)',
          },
          value: s.name,
          onChanged: (t) {
            final was = s.isSandpaper;
            s.name = t;
            if (!was && s.isSandpaper && s.kind == StockKind.material && s.unit == 'un') {
              s.unit = 'folha';
            }
            // virou lixa: atualiza a tela para mostrar folha/disco
            if (s.isSandpaper != was) setS(() {});
          },
        ),
        const SizedBox(height: 12),
        if (s.kind == StockKind.cliente) ...[
          Picker<String>(
            label: 'De qual carro',
            value: store.claimById(s.claimId) == null ? '' : s.claimId,
            values: ['', ...store.claims.map((c) => c.id)],
            labelOf: (id) {
              if (id.isEmpty) return 'Escolha o sinistro';
              final c = store.claimById(id)!;
              return [c.number, c.vehicle.plate, c.vehicle.model]
                  .where((e) => e.isNotEmpty)
                  .join(' · ');
            },
            onChanged: (id) => setS(() => s.claimId = id),
          ),
          const SizedBox(height: 12),
        ],
        if (s.kind == StockKind.peca) ...[
          BoundField(
            label: 'Serve em (carro / ano)',
            hint: 'Ex.: Gol G5 2009-2012',
            value: s.fits,
            onChanged: (t) => s.fits = t,
          ),
          const SizedBox(height: 12),
          BoundField(
            label: 'Código da peça (opcional)',
            value: s.partNumber,
            capitalization: TextCapitalization.characters,
            onChanged: (t) => s.partNumber = t,
          ),
          const SizedBox(height: 12),
        ],
        if (s.kind == StockKind.material)
          _SupplyUnits(item: s, setS: setS)
        else ...[
          Row(children: [
            Expanded(
              child: NumField(
                label: 'Quantidade em estoque',
                suffix: s.unit,
                value: s.qty,
                onChanged: (n) => s.qty = n,
              ),
            ),
            if (s.kind == StockKind.peca) ...[
              const SizedBox(width: 8),
              Expanded(
                child: NumField(
                  label: 'Custo (cada)',
                  prefix: 'R\$',
                  value: s.cost,
                  onChanged: (n) => s.cost = n,
                ),
              ),
            ],
          ]),
          if (s.kind == StockKind.peca) ...[
            const SizedBox(height: 12),
            NumField(
              label: 'Preço no orçamento (cada)',
              prefix: 'R\$',
              value: s.price,
              onChanged: (n) => s.price = n,
            ),
          ],
          const SizedBox(height: 12),
        ],
        Text('Onde está guardado', style: Theme.of(ctx).textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: BoundField(
              label: 'Corredor',
              value: s.corridor,
              capitalization: TextCapitalization.characters,
              onChanged: (t) => s.corridor = t,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BoundField(
              label: 'Prateleira',
              value: s.shelf,
              capitalization: TextCapitalization.characters,
              onChanged: (t) => s.shelf = t,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: BoundField(
              label: 'Nicho',
              value: s.slot,
              capitalization: TextCapitalization.characters,
              onChanged: (t) => s.slot = t,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        BoundField(
          label: 'Outro local (opcional)',
          hint: 'Ex.: mezanino, box 3',
          value: s.location,
          onChanged: (t) => s.location = t,
        ),
        const SizedBox(height: 12),
        BoundField(
          label: 'Observação',
          value: s.notes,
          maxLines: 2,
          onChanged: (t) => s.notes = t,
        ),
        if (canDelete) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, StockItem(id: '__delete__')),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir do estoque'),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Peças do estoque que servem para o item: escolher usar ou não.
Future<void> showStockFor(BuildContext context, Claim c, BudgetItem it) async {
  final store = StoreScope.read(context);
  final matches = stockFor(store.stock, it);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('No estoque para "${it.description}"',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Ao usar, o preço da peça vem do estoque e a baixa acontece quando o orçamento for aprovado.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final s in matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: StockThumb(item: s, size: 52),
                title: Text(s.name),
                subtitle: Text([
                  '${s.qtyLabel} em estoque',
                  if (s.fits.isNotEmpty) s.fits,
                  if (s.address.isNotEmpty) '📍 ${s.address}',
                  if (s.budgetPrice > 0) money(s.budgetPrice),
                ].join(' · ')),
                trailing: it.stockId == s.id
                    ? const Chip(label: Text('Em uso'))
                    : FilledButton(
                        onPressed: () {
                          it.stockId = s.id;
                          if (s.budgetPrice > 0) it.price = s.budgetPrice;
                          it.supplier = 'Estoque da oficina';
                          c.timeline.add(
                              TimelineEvent(text: 'Peça do estoque: ${s.name}'));
                          store.touch(c);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Usar'),
                      ),
              ),
            if (it.stockId.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    it.stockId = '';
                    if (it.supplier == 'Estoque da oficina') it.supplier = '';
                    store.touch(c);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Não usar o estoque (vou comprar)'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Endereço da busca da peça no Mercado Livre (peça + modelo + ano).
Uri marketSearchUri(BudgetItem it, Vehicle v) {
  final words = [it.description, v.model, v.year]
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[^\wÀ-ÿ ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return Uri.parse(
      'https://lista.mercadolivre.com.br/${Uri.encodeComponent(words.join('-')).replaceAll('%2D', '-')}');
}

Future<void> openMarketSearch(
    BuildContext context, BudgetItem it, Vehicle v) async {
  final uri = marketSearchUri(it, v);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, 'Não consegui abrir o navegador.');
  } catch (e) {
    if (context.mounted) toast(context, 'Não consegui abrir o navegador: $e');
  }
}

/// Etiquetas pequenas e clicáveis (estoque, Mercado Livre) na linha do item.
class LinkChip extends StatelessWidget {
  const LinkChip(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? brandSeed;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}


/// Unidades do insumo: como sai para o carro e como é comprado.
class _SupplyUnits extends StatelessWidget {
  const _SupplyUnits({required this.item, required this.setS});
  final StockItem item;
  final StateSetter setS;

  static const _units = ['ml', 'litro', 'g', 'kg', 'folha', 'disco', 'un', 'm', 'rolo', 'par'];
  static const _packs = ['lata', 'frasco', 'galão', 'quarto', 'balde', 'caixa', 'pacote', 'rolo'];

  @override
  Widget build(BuildContext context) {
    final s = item;
    final t = Theme.of(context);
    final units = {..._units, if (s.unit.isNotEmpty) s.unit}.toList();
    final packs = {..._packs, if (s.packName.isNotEmpty) s.packName}.toList();
    final perUnit = s.hasPack ? s.packCost / s.packSize : s.cost;
    final value = perUnit * (s.qty < 0 ? 0 : s.qty);
    final small = s.unit == 'ml' || s.unit == 'g';
    final tinyPack = s.hasPack && small && s.packSize < 20;
    final suspicious = (!s.hasPack && s.cost >= 5 && small) || tinyPack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('1. Como você compra', style: t.textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Em embalagem')),
            ButtonSegment(value: false, label: Text('Avulso')),
          ],
          selected: {s.hasPack},
          onSelectionChanged: (sel) => setS(() {
            if (sel.first) {
              final fromName = packFromName(s.name);
              if (fromName != null && fromName.$2 == s.unit) {
                s.packSize = fromName.$1;
              } else if (fromName != null && s.unit == 'ml' && fromName.$2 == 'litro') {
                s.packSize = fromName.$1 * 1000;
              } else {
                s.packSize = s.packSize > 0 ? s.packSize : 1;
              }
              if (s.packCost == 0 && s.cost > 0) s.packCost = s.cost;
              // estoque estava em embalagens: converte
              if (s.qty > 0 && s.qty < s.packSize) s.qty = s.qty * s.packSize;
            } else {
              s.syncPackCost();
              s.packSize = 0;
            }
          }),
        ),
        const SizedBox(height: 4),
        Text(
            s.hasPack
                ? 'Vem em lata, frasco, galão, caixa… Informe o preço da embalagem.'
                : 'Compra solto, na mesma unidade em que usa (ex.: por folha, por metro).',
            style: t.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (s.hasPack) ...[
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final p in packs)
              ChoiceChip(
                label: Text(p),
                selected: s.packName == p,
                onSelected: (_) => setS(() => s.packName = p),
              ),
          ]),
          const SizedBox(height: 12),
          NumField(
            label: 'Preço da ${s.packName}',
            prefix: 'R\$',
            value: s.packCost,
            onChanged: (n) => setS(() => s.packCost = n),
          ),
        ],
        const SizedBox(height: 16),
        Text('2. Como ele sai para o carro', style: t.textTheme.labelLarge),
        Text('A unidade usada na O.S. ao liberar o insumo.',
            style: t.textTheme.bodySmall),
        const SizedBox(height: 6),
        if (s.isSandpaper) ...[
          Wrap(spacing: 6, runSpacing: 4, children: [
            ChoiceChip(
              avatar: const Icon(Icons.crop_square, size: 18),
              label: const Text('Folha (corta em 4)'),
              selected: s.unit == 'folha',
              onSelected: (_) => setS(() {
                s.unit = 'folha';
                if (s.hasPack && s.packName == 'caixa') s.packName = 'pacote';
              }),
            ),
            ChoiceChip(
              avatar: const Icon(Icons.circle_outlined, size: 18),
              label: const Text('Disco'),
              selected: s.unit == 'disco',
              onSelected: (_) => setS(() {
                s.unit = 'disco';
                if (s.hasPack && s.packName == 'pacote') s.packName = 'caixa';
              }),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            s.unit == 'disco'
                ? 'Disco: sai inteiro na O.S. Se vem em caixa, use "Em embalagem" (ex.: caixa com 100 discos).'
                : 'Folha: estoque em folhas inteiras. Na O.S. sai em 1/4 de folha (um pedaço) ou 2/4 no taco (meia folha). O app desconta a fração certa.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],
        if (!s.isSandpaper)
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final u in units)
            ChoiceChip(
              label: Text(u),
              selected: s.unit == u,
              onSelected: (_) => setS(() => s.unit = u),
            ),
        ]),
        const SizedBox(height: 12),
        if (s.hasPack) ...[
          NumField(
            label: 'Cada ${s.packName} tem',
            suffix: s.unit,
            value: s.packSize,
            onChanged: (n) => setS(() {
              final packs = s.packs;
              s.packSize = n <= 0 ? 0.0001 : n;
              s.qty = packs * s.packSize;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ex.: lata de 900 ml, galão de 3,6 litro, caixa com 100 discos.',
                style: t.textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          Text('3. Quanto tem no estoque', style: t.textTheme.labelLarge),
          const SizedBox(height: 6),
          NumField(
            label: 'Quantidade de ${s.packName}s',
            value: s.packs,
            onChanged: (n) => setS(() => s.qty = n * s.packSize),
          ),
        ] else ...[
          NumField(
            label: 'Custo de 1 ${s.unit}',
            prefix: 'R\$',
            value: s.cost,
            onChanged: (n) => setS(() => s.cost = n),
          ),
          const SizedBox(height: 16),
          Text('3. Quanto tem no estoque', style: t.textTheme.labelLarge),
          const SizedBox(height: 6),
          NumField(
            label: 'Em estoque',
            suffix: s.unit,
            value: s.qty,
            onChanged: (n) => setS(() => s.qty = n),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('resumo-unidades'),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (suspicious ? Colors.orange : t.colorScheme.secondaryContainer)
                .withValues(alpha: suspicious ? 0.15 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (s.hasPack)
              Text('1 ${s.packName} = ${num2(s.packSize)} ${s.unit} por ${money(s.packCost)}'),
            Text('Custo por ${s.unit}: ${unitMoney(perUnit)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Em estoque: ${s.qtyLabel}'),
            Text('Valor parado no estoque: ${money(value)}'),
            if (suspicious)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    tinyPack
                        ? 'Confira: 1 ${s.packName} com só ${num2(s.packSize)} ${s.unit}? Se for 1 litro, escolha "litro" ou digite 1000 ml.'
                        : 'Confira: esse custo é de cada unidade. Se o preço é da lata/frasco, escolha "Em embalagem".',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
