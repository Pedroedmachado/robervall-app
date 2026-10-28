import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

final _picker = ImagePicker();

bool get _hasCamera => Platform.isAndroid || Platform.isIOS;

class PhotosTab extends StatefulWidget {
  const PhotosTab({super.key, required this.claim});
  final Claim claim;

  @override
  State<PhotosTab> createState() => _PhotosTabState();
}

class _PhotosTabState extends State<PhotosTab> {
  PhotoCategory _category = PhotoCategory.avaria;
  bool _busy = false;

  Future<void> _add(ImageSource source) async {
    final store = StoreScope.read(context);
    setState(() => _busy = true);
    try {
      final files = <XFile>[];
      if (source == ImageSource.camera) {
        final f = await _picker.pickImage(
            source: ImageSource.camera, maxWidth: 2200, imageQuality: 82);
        if (f != null) files.add(f);
      } else {
        files.addAll(
            await _picker.pickMultiImage(maxWidth: 2200, imageQuality: 82));
      }
      for (final f in files) {
        final bytes = await f.readAsBytes();
        final name = f.name;
        final dot = name.lastIndexOf('.');
        final ext = dot >= 0 ? name.substring(dot + 1) : 'jpg';
        await store.addPhoto(widget.claim, bytes, ext, category: _category);
      }
      if (files.isNotEmpty) {
        widget.claim.timeline.add(TimelineEvent(
            text: '${files.length} foto(s) adicionada(s) em ${_category.label}'));
        store.touch(widget.claim);
      }
    } catch (e) {
      if (mounted) toast(context, 'Não foi possível adicionar a foto: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = widget.claim;
    final t = Theme.of(context);

    final groups = <PhotoCategory, List<ClaimPhoto>>{};
    for (final p in c.photos) {
      groups.putIfAbsent(p.category, () => []).add(p);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: t.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 230,
                  child: Picker<PhotoCategory>(
                    label: 'Categoria das novas fotos',
                    value: _category,
                    values: PhotoCategory.values,
                    labelOf: (e) => e.label,
                    onChanged: (e) => setState(() => _category = e),
                  ),
                ),
                if (_hasCamera)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _add(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Câmera'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _add(ImageSource.gallery),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_hasCamera ? 'Galeria' : 'Adicionar imagens'),
                ),
                if (_busy)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: c.photos.isEmpty
              ? const EmptyState(
                  icon: Icons.photo_library_outlined,
                  text:
                      'Nenhuma foto ainda.\nRegistre as avarias, o veículo inteiro, documentos e o antes/depois do reparo.',
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final cat in PhotoCategory.values)
                      if (groups[cat] != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Text('${cat.label} (${groups[cat]!.length})',
                              style: t.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: groups[cat]!.length,
                          itemBuilder: (context, i) {
                            final p = groups[cat]![i];
                            return _Thumb(
                              file: store.photoFile(p),
                              caption: p.caption,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PhotoViewer(
                                    claim: c,
                                    initial: c.photos.indexOf(p),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.caption, required this.onTap});
  final File file;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Material(
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                file,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image)),
              ),
              if (caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.claim, required this.initial});
  final Claim claim;
  final int initial;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final photos = widget.claim.photos;
    if (photos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const Scaffold(backgroundColor: Colors.black);
    }
    if (_index >= photos.length) _index = photos.length - 1;
    final p = photos[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} de ${photos.length} · ${p.category.label}'),
        actions: [
          IconButton(
            tooltip: 'Legenda',
            icon: const Icon(Icons.edit_note),
            onPressed: () async {
              final ctl = TextEditingController(text: p.caption);
              final r = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Legenda da foto'),
                  content: TextField(
                    controller: ctl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Ex.: amassado na porta dianteira'),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
                        child: const Text('Salvar')),
                  ],
                ),
              );
              if (r != null) {
                p.caption = r;
                store.touch(widget.claim);
              }
            },
          ),
          PopupMenuButton<PhotoCategory>(
            tooltip: 'Mudar categoria',
            icon: const Icon(Icons.label_outline),
            onSelected: (cat) {
              p.category = cat;
              store.touch(widget.claim);
            },
            itemBuilder: (_) => [
              for (final cat in PhotoCategory.values)
                CheckedPopupMenuItem(
                    value: cat, checked: cat == p.category, child: Text(cat.label)),
            ],
          ),
          IconButton(
            tooltip: 'Excluir foto',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, 'Excluir foto?',
                  'A foto será apagada deste aparelho.',
                  ok: 'Excluir', danger: true)) {
                await store.removePhoto(widget.claim, p);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    store.photoFile(photos[i]),
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 64),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black,
            child: Text(
              '${p.caption.isEmpty ? 'Sem legenda' : p.caption} · ${dateTime(p.takenAt)}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
