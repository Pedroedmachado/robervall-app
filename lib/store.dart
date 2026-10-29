import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'finance.dart';
import 'seed.dart';

/// Armazenamento local (offline) em JSON + pasta de fotos.
class AppStore extends ChangeNotifier {
  AppStore._(this.baseDir);

  final Directory baseDir;
  Settings settings = Settings();
  final List<Claim> claims = [];
  final List<Contact> contacts = [];
  final List<CatalogItem> catalog = [];
  final List<FinanceEntry> entries = [];
  Timer? _saveTimer;
  bool _saving = false;
  bool _pendingSave = false;

  Directory get photosDir => Directory('${baseDir.path}/fotos');
  File get _dataFile => File('${baseDir.path}/dados.json');

  /// Abre os dados. [dir] (ou a variável FUNILAR_DATA_DIR) troca a pasta,
  /// útil para testes.
  static Future<AppStore> open({Directory? dir}) async {
    final env = Platform.environment['FUNILAR_DATA_DIR'];
    if (dir == null && env != null && env.isNotEmpty) dir = Directory(env);
    if (dir == null) {
      final support = (await getApplicationSupportDirectory()).path;
      dir = Directory('$support/funilar');
      // migra os dados da versão com o nome antigo, se existirem
      // (o ID antigo era br.com.robervall, então a pasta-mãe também mudou)
      if (!await dir.exists()) {
        for (final old in [
          Directory('$support/robervall'),
          Directory('${support.replaceAll('funilar', 'robervall')}/robervall'),
        ]) {
          if (await old.exists()) {
            try {
              await old.rename(dir.path);
            } catch (_) {}
            break;
          }
        }
      }
    }
    await dir.create(recursive: true);
    final store = AppStore._(dir);
    await store.photosDir.create(recursive: true);
    await store._load();
    return store;
  }

  Future<void> _load() async {
    final f = _dataFile;
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) _fromJson(Map<String, dynamic>.from(j));
        return;
      } catch (e) {
        debugPrint('Falha ao ler dados: $e');
        // guarda o arquivo corrompido para não perder nada
        await f.copy('${f.path}.corrompido-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    catalog.addAll(defaultCatalog());
    await _write();
  }

  void _fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(Object? v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final s = j['settings'];
    settings = s is Map
        ? Settings.fromJson(Map<String, dynamic>.from(s))
        : Settings();
    claims
      ..clear()
      ..addAll(list(j['claims']).map(Claim.fromJson));
    // versões anteriores criavam uma linha por operação da mesma peça
    for (final c in claims) {
      c.items = mergePartLines(c.items);
    }
    contacts
      ..clear()
      ..addAll(list(j['contacts']).map(Contact.fromJson));
    catalog
      ..clear()
      ..addAll(list(j['catalog']).map(CatalogItem.fromJson));
    entries
      ..clear()
      ..addAll(list(j['entries']).map(FinanceEntry.fromJson));
  }

  Map<String, dynamic> toJson() => {
        'app': 'funilar',
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'settings': settings.toJson(),
        'claims': claims.map((e) => e.toJson()).toList(),
        'contacts': contacts.map((e) => e.toJson()).toList(),
        'catalog': catalog.map((e) => e.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  Future<void> _write() async {
    if (_saving) {
      _pendingSave = true;
      return;
    }
    _saving = true;
    try {
      final tmp = File('${_dataFile.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()), flush: true);
      await tmp.rename(_dataFile.path);
    } catch (e) {
      debugPrint('Falha ao salvar: $e');
    } finally {
      _saving = false;
      if (_pendingSave) {
        _pendingSave = false;
        await _write();
      }
    }
  }

  /// Notifica a interface e agenda gravação em disco.
  void changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _write);
  }

  Timer? _notifyTimer;

  /// Edição de texto: grava e atualiza a interface quando a pessoa para de
  /// digitar (título, lista e totais acompanham o que foi digitado).
  void saveLater([Claim? c]) {
    if (c != null) c.updatedAt = DateTime.now();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _write);
    _notifyTimer?.cancel();
    _notifyTimer = Timer(const Duration(milliseconds: 350), notifyListeners);
  }

  /// Registro recém-criado que ficou sem nenhuma informação.
  bool isBlank(Claim c) =>
      c.customerName.trim().isEmpty &&
      c.vehicle.plate.trim().isEmpty &&
      c.vehicle.brand.trim().isEmpty &&
      c.vehicle.model.trim().isEmpty &&
      c.claimNumber.trim().isEmpty &&
      c.insurerName.trim().isEmpty &&
      c.description.trim().isEmpty &&
      c.accidentDate == null &&
      c.dueDate == null &&
      c.items.isEmpty &&
      c.photos.isEmpty &&
      c.damages.isEmpty &&
      c.timeline.length <= 1;

  /// Remove um registro vazio (aberto por engano) e devolve o número.
  void discardIfBlank(Claim c) {
    if (!claims.contains(c) || !isBlank(c)) return;
    claims.remove(c);
    final expected =
        '${settings.numberPrefix}-${(settings.nextNumber - 1).toString().padLeft(4, '0')}';
    if (c.number == expected) settings.nextNumber--;
    changed();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _write();
  }

  // ---------------------------------------------------------------- sinistros

  Claim newClaim() {
    final c = Claim(
      number:
          '${settings.numberPrefix}-${settings.nextNumber.toString().padLeft(4, '0')}',
    );
    settings.nextNumber++;
    c.timeline.add(TimelineEvent(text: 'Registro criado', isStatus: true));
    claims.insert(0, c);
    changed();
    return c;
  }

  Claim? claimById(String id) {
    for (final c in claims) {
      if (c.id == id) return c;
    }
    return null;
  }

  void touch(Claim c) {
    c.updatedAt = DateTime.now();
    changed();
  }

  void setStatus(Claim c, ClaimStatus s, {String? note}) {
    if (c.status == s) return;
    c.status = s;
    // orçamento fechado: a data de aprovação é a data da receita
    if (isClosedStatus(s) && c.approvedAt == null) c.approvedAt = DateTime.now();
    c.timeline.add(TimelineEvent(
      text: 'Status: ${s.label}${note == null || note.isEmpty ? '' : ' — $note'}',
      isStatus: true,
    ));
    touch(c);
  }

  Claim duplicate(Claim c) {
    final j = c.toJson();
    final copy = Claim.fromJson(j);
    copy.id = newId();
    copy.number =
        '${settings.numberPrefix}-${settings.nextNumber.toString().padLeft(4, '0')}';
    settings.nextNumber++;
    copy.status = ClaimStatus.aberto;
    copy.photos = [];
    final newIds = <String, String>{};
    copy.items = c.items.map((e) {
      final n = e.copy();
      newIds[e.id] = n.id;
      return n;
    }).toList();
    for (final it in copy.items) {
      if (it.parentId.isNotEmpty) it.parentId = newIds[it.parentId] ?? '';
    }
    copy.timeline = [
      TimelineEvent(text: 'Duplicado de ${c.number}', isStatus: true)
    ];
    copy.createdAt = DateTime.now();
    copy.updatedAt = DateTime.now();
    copy.approvedAt = null;
    copy.approvedBy = '';
    claims.insert(0, copy);
    changed();
    return copy;
  }

  Future<void> deleteClaim(Claim c) async {
    for (final p in c.photos) {
      final f = photoFile(p);
      if (await f.exists()) await f.delete();
    }
    claims.remove(c);
    changed();
  }

  // ------------------------------------------------------------------- fotos

  File photoFile(ClaimPhoto p) => File('${photosDir.path}/${p.fileName}');

  Future<ClaimPhoto> addPhoto(Claim c, Uint8List bytes, String ext,
      {PhotoCategory category = PhotoCategory.avaria}) async {
    final e = ext.isEmpty ? 'jpg' : ext.toLowerCase().replaceAll('.', '');
    final name = '${c.id}_${newId()}.$e';
    await File('${photosDir.path}/$name').writeAsBytes(bytes, flush: true);
    final p = ClaimPhoto(fileName: name, category: category);
    c.photos.add(p);
    touch(c);
    return p;
  }

  Future<void> removePhoto(Claim c, ClaimPhoto p) async {
    final f = photoFile(p);
    if (await f.exists()) await f.delete();
    c.photos.remove(p);
    touch(c);
  }

  // ---------------------------------------------------------------- contatos

  void upsertContact(Contact ct) {
    if (!contacts.contains(ct)) contacts.add(ct);
    contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    changed();
  }

  void removeContact(Contact ct) {
    contacts.remove(ct);
    changed();
  }

  List<Contact> contactsOf(ContactKind k) =>
      contacts.where((c) => c.kind == k).toList();

  /// Salva automaticamente cliente e seguradora do sinistro nos cadastros.
  void rememberContactsFrom(Claim c) {
    bool exists(ContactKind k, String name) => contacts.any((e) =>
        e.kind == k && e.name.trim().toLowerCase() == name.trim().toLowerCase());
    var added = false;
    if (c.customerName.trim().isNotEmpty &&
        !exists(ContactKind.cliente, c.customerName)) {
      contacts.add(Contact(
        kind: ContactKind.cliente,
        name: c.customerName.trim(),
        phone: c.customerPhone,
        email: c.customerEmail,
        doc: c.customerDoc,
      ));
      added = true;
    }
    if (c.insurerName.trim().isNotEmpty &&
        !exists(ContactKind.seguradora, c.insurerName)) {
      contacts.add(Contact(kind: ContactKind.seguradora, name: c.insurerName.trim()));
      added = true;
    }
    if (c.regulatorName.trim().isNotEmpty &&
        !exists(ContactKind.regulador, c.regulatorName)) {
      contacts.add(Contact(
        kind: ContactKind.regulador,
        name: c.regulatorName.trim(),
        phone: c.regulatorContact,
      ));
      added = true;
    }
    if (added) {
      contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      changed();
    }
  }

  // ---------------------------------------------------------------- catálogo

  void upsertCatalog(CatalogItem it) {
    if (!catalog.contains(it)) catalog.add(it);
    catalog.sort((a, b) =>
        a.description.toLowerCase().compareTo(b.description.toLowerCase()));
    changed();
  }

  void removeCatalog(CatalogItem it) {
    catalog.remove(it);
    changed();
  }

  // ------------------------------------------------------------------ backup

  /// Gera um .zip com dados.json e todas as fotos.
  Future<Uint8List> exportBackup() async {
    await flush();
    final archive = Archive();
    final data = utf8.encode(jsonEncode(toJson()));
    archive.addFile(ArchiveFile('dados.json', data.length, data));
    if (await photosDir.exists()) {
      await for (final e in photosDir.list()) {
        if (e is File) {
          final bytes = await e.readAsBytes();
          final name = e.uri.pathSegments.last;
          archive.addFile(ArchiveFile('fotos/$name', bytes.length, bytes));
        }
      }
    }
    final out = ZipEncoder().encode(archive);
    // ignore: dead_null_aware_expression, unnecessary_null_in_if_null_operators
    return Uint8List.fromList(out ?? const <int>[]);
  }

  /// Restaura um backup .zip (substitui os dados atuais).
  Future<void> importBackup(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    Map<String, dynamic>? data;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name == 'dados.json') {
        final j = jsonDecode(utf8.decode(f.content as List<int>));
        if (j is Map) data = Map<String, dynamic>.from(j);
      }
    }
    // aceita também backups do nome antigo do app (Robervall)
    if (data == null ||
        (data['app'] != 'funilar' && data['app'] != 'robervall')) {
      throw const FormatException('Arquivo não é um backup do Funilar.');
    }
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('fotos/')) continue;
      final name = f.name.substring('fotos/'.length);
      if (name.isEmpty || name.contains('/') || name.contains('\\') || name.contains('..')) {
        continue;
      }
      await File('${photosDir.path}/$name')
          .writeAsBytes(f.content as List<int>, flush: true);
    }
    _fromJson(data);
    changed();
    await flush();
  }

  // -------------------------------------------------------------- financeiro

  void upsertEntry(FinanceEntry e) {
    if (!entries.contains(e)) entries.add(e);
    entries.sort((a, b) => b.date.compareTo(a.date));
    changed();
  }

  void removeEntry(FinanceEntry e) {
    entries.remove(e);
    changed();
  }

  // ------------------------------------------------------------- utilidades

  List<Claim> get openClaims => claims.where((c) => c.status.isOpen).toList();
}
