import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'finance.dart';
import 'format.dart' show hideMoney, num2;
import 'licensing.dart';
import 'modules.dart';
import 'seed.dart';
import 'stock.dart';

/// Armazenamento local (offline) em JSON + pasta de fotos.
class AppStore extends ChangeNotifier {
  AppStore._(this.baseDir);

  final Directory baseDir;
  Settings settings = Settings();
  final List<Claim> claims = [];
  final List<Contact> contacts = [];
  final List<CatalogItem> catalog = [];
  final List<FinanceEntry> entries = [];
  final List<StockItem> stock = [];

  /// Usuários da oficina (vazio = uso individual, acesso total).
  final List<AppUser> users = [];

  /// Campos do arquivo que esta versão não conhece: são guardados de volta
  /// sem alteração (nada some ao gravar).
  final Map<String, dynamic> _extra = {};

  /// Licença conferida, código deste aparelho e módulos ligados aqui.
  LicenseCheck license = const LicenseCheck(LicenseStatus.missing);
  String deviceId = '';
  Activation activation = Activation();
  String _publicKey = productionPublicKey;

  File get _licenseFile => File('${baseDir.path}/licenca.lic');
  File get _activationFile => File('${baseDir.path}/modulos.json');

  /// Usuário logado (null com até 1 usuário: entra direto).
  AppUser? currentUser;

  List<AppUser> get activeUsers => users.where((u) => u.active).toList();

  /// Com mais de um usuário, o app pede login.
  bool get needsLogin => activeUsers.length > 1 && currentUser == null;

  Timer? _saveTimer;
  bool _saving = false;
  bool _pendingSave = false;

  Directory get photosDir => Directory('${baseDir.path}/fotos');
  File get _dataFile => File('${baseDir.path}/dados.json');

  /// Abre os dados. [dir] (ou a variável FUNILAR_DATA_DIR) troca a pasta,
  /// útil para testes.
  static Future<AppStore> open({
    Directory? dir,
    @visibleForTesting License? assumeLicense,
    @visibleForTesting String? publicKey,
    @visibleForTesting String? device,
    @visibleForTesting bool enforceLicense = false,
  }) async {
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
    if (publicKey != null) store._publicKey = publicKey;
    store.deviceId = device ?? await computeDeviceId(dir);
    store._enforceLicense = enforceLicense;
    await store._loadLicensing(assumeLicense);
    await store._migrateAccess();
    store._applyAccess();
    // custos da equipe no formato novo (antes só existia o pintor)
    if (store.entries.any((e) => e.autoKey == painterAutoKey)) {
      for (final c in store.claims) {
        store.syncCrewCosts(c);
      }
      store.entries.removeWhere((e) => e.autoKey == painterAutoKey);
    }
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

  static const _knownKeys = {
    'app', 'version', 'savedAt', 'settings', 'claims', 'contacts',
    'catalog', 'entries', 'stock', 'users',
  };

  void _fromJson(Map<String, dynamic> j) {
    _extra
      ..clear()
      ..addEntries(j.entries.where((e) => !_knownKeys.contains(e.key)));
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
    stock
      ..clear()
      ..addAll(list(j['stock']).map(StockItem.fromJson));
    users
      ..clear()
      ..addAll(list(j['users']).map(AppUser.fromJson));
  }

  Map<String, dynamic> toJson() => {
        ..._extra,
        'app': 'funilar',
        'version': 1,
        'savedAt': DateTime.now().toIso8601String(),
        'settings': settings.toJson(),
        'claims': claims.map((e) => e.toJson()).toList(),
        'contacts': contacts.map((e) => e.toJson()).toList(),
        'catalog': catalog.map((e) => e.toJson()).toList(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'stock': stock.map((e) => e.toJson()).toList(),
        'users': users.map((e) => e.toJson()).toList(),
      };

  Future<void> _write() async {
    // sem licença válida: só consulta, nada é gravado
    if (gate.readOnly) return;
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
    gate.requirePerm(Perm.sinistroEditar);
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
    syncCrewCosts(c);
    syncStock(c);
    changed();
  }

  Contact? contactById(String id) {
    if (id.isEmpty) return null;
    for (final c in contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Mantém no Financeiro o custo de cada profissional do carro (pintor,
  /// funileiro, martelinho…): lançado quando o orçamento está fechado,
  /// atualizado se o orçamento ou o valor mudar e removido se a pessoa sair
  /// da equipe ou o orçamento deixar de estar fechado.
  void syncCrewCosts(Claim c) {
    // módulo desligado: congela (nada é criado nem apagado) até reativar
    if (!gate.active(Mod.equipe) || !gate.active(Mod.financeiro)) return;
    final existing =
        entries.where((e) => e.claimId == c.id && isCrewEntry(e)).toList();
    final keep = <FinanceEntry>{};
    final active = isClosedStatus(c.status) && claims.contains(c);
    if (active) {
      for (final m in c.crew) {
        final w = contactById(m.contactId);
        if (w == null) continue;
        final cost = crewCost(c, m, w);
        if (cost.amount <= 0) continue;
        final id = 'equipe-${c.id}-${m.id}';
        final found = existing.where((e) => e.id == id);
        final e = found.isNotEmpty
            ? found.first
            : FinanceEntry(id: id, autoKey: crewAutoKey);
        e
          ..isIncome = false
          ..category = ExpenseCategory.funcionario
          ..outsourced = w.outsourced
          ..service = m.role
          ..payType = cost.payType
          ..pieces = cost.pieces
          ..pieceValue = cost.rate
          ..amount = cost.amount
          ..contact = w.name
          ..claimId = c.id
          ..recurring = false
          ..description =
              '${m.role.label} ${c.number}${c.vehicle.plate.isEmpty ? '' : ' · ${c.vehicle.plate}'}'
          ..date = closedDate(c);
        keep.add(e);
        if (found.isEmpty) entries.add(e);
      }
    }
    entries.removeWhere((e) => existing.contains(e) && !keep.contains(e));
  }

  StockItem? stockById(String id) {
    if (id.isEmpty) return null;
    for (final s in stock) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Dá baixa no estoque das peças usadas quando o orçamento fecha, e
  /// devolve se ele reabrir, se o item sair ou trocar de peça.
  void syncStock(Claim c) {
    if (!gate.active(Mod.estoque)) return; // congelado até reativar
    final want = <String, StockUse>{};
    if (isClosedStatus(c.status) && claims.contains(c)) {
      for (final it in c.items) {
        if (it.stockId.isEmpty || !it.approved || it.op != ItemOp.troca) continue;
        if (stockById(it.stockId) == null) continue;
        want[it.id] = StockUse(it.stockId, it.qty <= 0 ? 1 : it.qty);
      }
    }
    // devolve o que não deveria mais estar fora
    for (final e in c.stockTaken.entries.toList()) {
      final w = want[e.key];
      if (w != null && w.stockId == e.value.stockId && w.qty == e.value.qty) {
        continue;
      }
      stockById(e.value.stockId)?.qty += e.value.qty;
      c.stockTaken.remove(e.key);
    }
    // tira o que falta
    for (final e in want.entries) {
      if (c.stockTaken.containsKey(e.key)) continue;
      stockById(e.value.stockId)?.qty -= e.value.qty;
      c.stockTaken[e.key] = e.value;
    }
  }

  /// Dá saída de um insumo do estoque para a O.S. (só o gestor libera).
  SupplyUse issueSupply(Claim c, StockItem s, double qty,
      {String itemId = '', String note = ''}) {
    gate.require(Mod.producao);
    gate.require(Mod.estoque);
    gate.requireWrite();
    final u = SupplyUse(
      stockId: s.id,
      name: s.name,
      qty: qty,
      unit: s.unit,
      unitCost: s.cost,
      itemId: itemId,
      note: note,
    );
    s.qty -= qty;
    c.supplies.add(u);
    c.timeline.add(TimelineEvent(
        text: 'Insumo liberado: ${s.name} (${qtyText(qty, s.unit)})'));
    touch(c);
    return u;
  }

  /// Desfaz a saída do insumo (volta para o estoque).
  void returnSupply(Claim c, SupplyUse u) {
    gate.require(Mod.producao);
    gate.require(Mod.estoque);
    gate.requireWrite();
    stockById(u.stockId)?.qty += u.qty;
    c.supplies.remove(u);
    touch(c);
  }

  /// Sinistros que usam (ou reservam) uma peça do estoque.
  List<Claim> claimsUsingStock(StockItem s) => claims
      .where((c) => c.items.any((i) => i.stockId == s.id))
      .toList();

  void upsertStock(StockItem s) {
    gate.require(Mod.estoque);
    gate.requireWrite();
    if (!stock.contains(s)) stock.add(s);
    stock.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    changed();
  }

  Future<void> removeStock(StockItem s) async {
    gate.require(Mod.estoque);
    gate.requireWrite();
    stock.remove(s);
    for (final c in claims) {
      for (final it in c.items) {
        if (it.stockId == s.id) it.stockId = '';
      }
      c.stockTaken.removeWhere((_, u) => u.stockId == s.id);
    }
    changed();
  }

  /// Guarda a foto de um item do estoque e devolve o nome do arquivo.
  Future<String> saveStockPhoto(StockItem s, Uint8List bytes) async {
    gate.require(Mod.estoque);
    final name = 'estoque_${s.id}_${newId()}.jpg';
    await File('${photosDir.path}/$name').writeAsBytes(bytes, flush: true);
    return name;
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
    gate.requirePerm(Perm.sinistroEditar);
    final j = c.toJson();
    final copy = Claim.fromJson(j);
    copy.id = newId();
    copy.number =
        '${settings.numberPrefix}-${settings.nextNumber.toString().padLeft(4, '0')}';
    settings.nextNumber++;
    copy.status = ClaimStatus.aberto;
    copy.photos = [];
    copy.stockTaken = {};
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
    gate.requirePerm(Perm.sinistroEditar);
    for (final p in c.photos) {
      final f = photoFile(p);
      if (await f.exists()) await f.delete();
    }
    claims.remove(c);
    syncStock(c); // devolve as peças ao estoque
    entries.removeWhere((e) => e.claimId == c.id && isCrewEntry(e));
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
    gate.requireWrite();
    if (!contacts.contains(ct)) contacts.add(ct);
    // valor do funcionário mudou: atualiza os custos lançados
    for (final c in claims) {
      if (c.crew.any((m) => m.contactId == ct.id)) syncCrewCosts(c);
    }
    contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    changed();
  }

  void removeContact(Contact ct) {
    gate.requirePerm(Perm.cadastrosEditar);
    contacts.remove(ct);
    for (final c in claims) {
      if (c.crew.any((m) => m.contactId == ct.id)) {
        c.crew.removeWhere((m) => m.contactId == ct.id);
        syncCrewCosts(c);
      }
    }
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
    gate.requirePerm(Perm.orcamentoEditar);
    if (!catalog.contains(it)) catalog.add(it);
    catalog.sort((a, b) =>
        a.description.toLowerCase().compareTo(b.description.toLowerCase()));
    changed();
  }

  void removeCatalog(CatalogItem it) {
    gate.requirePerm(Perm.orcamentoEditar);
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
    gate.requirePerm(Perm.ajustes);
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
    gate.require(Mod.financeiro);
    gate.requirePerm(Perm.financeiroEditar);
    if (!entries.contains(e)) entries.add(e);
    entries.sort((a, b) => b.date.compareTo(a.date));
    changed();
  }

  void removeEntry(FinanceEntry e) {
    gate.require(Mod.financeiro);
    gate.requirePerm(Perm.financeiroEditar);
    entries.remove(e);
    changed();
  }

  // ------------------------------------------------------------- utilidades

  List<Claim> get openClaims => claims.where((c) => c.status.isOpen).toList();

  // ------------------------------------------------- licença e módulos

  /// O app é liberado por completo para quem o tiver: a licença não é
  /// exigida. O mecanismo (licença assinada, módulos, Master) continua no
  /// código e só é ligado nos testes ([enforceLicense]).
  bool _enforceLicense = false;

  Future<void> _loadLicensing(License? assume) async {
    if (!_enforceLicense && assume == null) {
      license = LicenseCheck(LicenseStatus.valid,
          License.full(customer: settings.shopName.isEmpty ? 'Funilar' : settings.shopName));
      final act = await Activation.load(_activationFile, deviceId);
      activation = act ?? Activation();
      if (act?.tampered == true) activation = Activation(log: act!.log);
      // versão completa: todos os módulos ligados
      activation.enabled = Mod.values.toSet();
      activation.lastSeen = DateTime.now();
      await activation.save(_activationFile, deviceId);
      return;
    }
    final act = await Activation.load(_activationFile, deviceId);
    if (assume != null) {
      license = LicenseCheck(LicenseStatus.valid, assume);
    } else {
      final text =
          await _licenseFile.exists() ? await _licenseFile.readAsString() : null;
      license = await verifyLicense(text,
          deviceId: deviceId, lastSeen: act?.lastSeen, publicKey: _publicKey);
    }
    final licensed = license.ok ? license.license!.modules : <Mod>{};
    if (act == null || act.tampered) {
      // primeiro uso (ou arquivo mexido): liga tudo o que a licença autoriza
      activation = Activation(enabled: {...licensed}, lastSeen: act?.lastSeen);
      if (act?.tampered == true) {
        activation.log.add(_logEntry('aviso', null,
            'Arquivo de módulos alterado fora do app: voltou ao padrão da licença'));
      }
    } else {
      activation = act;
    }
    // guarda a maior data vista (detecta relógio atrasado)
    final now = DateTime.now();
    if (license.ok &&
        (activation.lastSeen == null || now.isAfter(activation.lastSeen!))) {
      activation.lastSeen = now;
    }
    await activation.save(_activationFile, deviceId);
  }

  Map<String, dynamic> _logEntry(String action, Mod? m, String note) => {
        'quando': DateTime.now().toIso8601String(),
        'acao': action,
        if (m != null) 'modulo': m.name,
        'obs': note,
      };

  /// Aplica licença, ativação e usuário na checagem central.
  void _applyAccess() {
    final licensed = license.ok ? license.license!.modules : <Mod>{};
    gate
      ..licensed = {...licensed}
      ..enabled = {...activation.enabled}
      ..readOnly = !license.ok;
    final act = activeUsers;
    if (currentUser != null && !act.contains(currentUser)) currentUser = null;
    if (act.length == 1) currentUser = act.single;
    gate.user = currentUser;
    gate.locked = needsLogin;
    hideMoney = !gate.can(Perm.valoresVer);
  }

  /// Instala uma licença (texto colado ou arquivo). Só grava se for válida.
  Future<LicenseCheck> installLicense(String text) async {
    final check = await verifyLicense(text,
        deviceId: deviceId,
        lastSeen: activation.lastSeen,
        publicKey: _publicKey);
    if (!check.ok) return check;
    final wasOk = license.ok;
    final before = license.ok ? license.license!.modules : <Mod>{};
    license = check;
    await _licenseFile.writeAsString(text.trim(), flush: true);
    // módulos novos na licença já entram ligados
    final added = check.license!.modules.difference(before);
    activation.enabled.addAll(added);
    activation.lastSeen = DateTime.now();
    activation.log.add(_logEntry('licenca', null,
        'Licença ${check.license!.id} instalada (${check.license!.customer})'));
    await activation.save(_activationFile, deviceId);
    _applyAccess();
    if (!wasOk) await _migrateAccess();
    _reconcileAll();
    changed();
    return check;
  }

  /// Impacto de ligar/desligar um módulo (Master). Lista de bloqueios vazia
  /// = pode confirmar.
  ModuleImpact impactOf(Mod m, bool turnOn) {
    final blocks = <String>[];
    final notes = <String>[];
    if (m == Mod.nucleo) {
      blocks.add('O Núcleo não pode ser desligado.');
    } else if (turnOn) {
      if (!gate.licensed.contains(m)) {
        blocks.add('A licença deste cliente não autoriza ${m.label}.');
      }
      for (final d in m.requires) {
        if (!gate.active(d)) {
          blocks.add('Ligue antes o módulo ${d.label} (é obrigatório para ${m.label}).');
        }
      }
      for (final (d, why) in m.softRequires) {
        if (!gate.active(d)) notes.add('Atenção: $why.');
      }
      notes.add('Os dados guardados de ${m.label} voltam a aparecer como estavam.');
      if (m == Mod.estoque) {
        notes.add('Baixas e devoluções pendentes serão acertadas agora.');
      }
      if (m == Mod.equipe || m == Mod.financeiro) {
        notes.add('Custos da equipe pendentes serão lançados agora.');
      }
    } else {
      for (final other in Mod.values) {
        if (other.requires.contains(m) && gate.active(other)) {
          blocks.add('${other.label} depende de ${m.label}: desligue ${other.label} antes.');
        }
        for (final (d, why) in other.softRequires) {
          if (d == m && gate.active(other)) notes.add('${other.label}: $why.');
        }
      }
      notes.addAll(m.offEffects);
      notes.add('Nenhum dado é apagado: ${_dataSummary(m)}.');
    }
    return ModuleImpact(blocks, notes);
  }

  String _dataSummary(Mod m) {
    int n(Iterable it) => it.length;
    return switch (m) {
      Mod.vistoria =>
        '${n(claims.where((c) => c.damages.isNotEmpty || c.preDamages.isNotEmpty || !c.reception.isEmpty))} sinistros com vistoria e ${claims.fold(0, (a, c) => a + c.photos.length)} fotos ficam guardados',
      Mod.financeiro => '${entries.length} lançamentos ficam guardados',
      Mod.ocr => '${n(entries.where((e) => e.receiptFile.isNotEmpty))} notas anexadas ficam guardadas',
      Mod.equipe => '${n(claims.where((c) => c.crew.isNotEmpty))} carros com equipe ficam guardados',
      Mod.estoque => '${stock.length} itens do estoque ficam guardados',
      Mod.producao =>
        '${claims.fold(0, (a, c) => a + c.supplies.length)} saídas de insumo e as tarefas marcadas ficam guardadas',
      Mod.integracoes => 'os valores FIPE já consultados continuam nos sinistros',
      Mod.nucleo => '',
    };
  }

  /// Liga/desliga um módulo. Só com sessão Master válida.
  Future<void> setModuleEnabled(Mod m, bool on, MasterSession session) async {
    if (!session.valid) throw AccessDenied('Acesso Master necessário.');
    final impact = impactOf(m, on);
    if (impact.blocks.isNotEmpty) throw AccessDenied(impact.blocks.join(' '));
    on ? activation.enabled.add(m) : activation.enabled.remove(m);
    activation.log.add(_logEntry(on ? 'ligou' : 'desligou', m, 'Master'));
    // vale na hora; o arquivo é gravado em seguida
    _applyAccess();
    if (on) _reconcileAll();
    changed();
    await activation.save(_activationFile, deviceId);
  }

  /// Reativação: acerta o que ficou congelado (custos e estoque).
  void _reconcileAll() {
    for (final c in claims) {
      syncCrewCosts(c);
      syncStock(c);
    }
  }

  /// Confere a resposta do fornecedor ao desafio Master.
  Future<MasterSession> openMaster(String challenge, String response) async {
    final ok = await verifyMasterResponse(challenge, response, publicKey: _publicKey);
    if (ok) {
      activation.log.add(_logEntry('master', null, 'Acesso Master'));
      await activation.save(_activationFile, deviceId);
    }
    return MasterSession._(ok);
  }

  // ---------------------------------------------------------------- usuários

  /// Versões anteriores: o PIN do gestor vira o primeiro Administrador; o
  /// modo produção vira um usuário Produção.
  Future<void> _migrateAccess() async {
    if (users.isNotEmpty || settings.managerPin.isEmpty) return;
    final (h, salt) = await hashPin(settings.managerPin);
    users.add(AppUser(
        id: newId(), name: 'Gestor', role: Role.admin, pinHash: h, salt: salt));
    if (settings.productionMode) {
      users.add(AppUser(id: newId(), name: 'Produção', role: Role.producao));
    }
    settings.managerPin = '';
    settings.productionMode = false;
    changed();
  }

  Future<AppUser> saveUser(AppUser u, {String? newPin}) async {
    gate.requirePerm(Perm.usuarios);
    if (newPin != null) {
      if (newPin.isEmpty) {
        u.pinHash = '';
        u.salt = '';
      } else {
        final (h, salt) = await hashPin(newPin);
        u.pinHash = h;
        u.salt = salt;
      }
    }
    if (!users.contains(u)) users.add(u);
    _checkAdmins();
    _applyAccess();
    changed();
    return u;
  }

  void _checkAdmins() {
    final admins =
        users.where((x) => x.active && x.role == Role.admin && x.pinHash.isNotEmpty);
    if (users.any((x) => x.active) && admins.isEmpty) {
      throw AccessDenied(
          'Precisa ficar pelo menos um Administrador ativo com PIN.');
    }
  }

  /// Desativa (não apaga) um usuário.
  void setUserActive(AppUser u, bool active) {
    gate.requirePerm(Perm.usuarios);
    final before = u.active;
    u.active = active;
    try {
      _checkAdmins();
    } catch (_) {
      u.active = before;
      rethrow;
    }
    if (currentUser == u && !active) currentUser = null;
    _applyAccess();
    changed();
  }

  Future<bool> login(AppUser u, String pin) async {
    if (!u.active || !await checkPin(u, pin)) return false;
    currentUser = u;
    _applyAccess();
    notifyListeners();
    return true;
  }

  void logout() {
    currentUser = null;
    _applyAccess();
    notifyListeners();
  }

  /// Autorização pontual de outro usuário (ex.: almoxarife libera insumo
  /// no tablet da produção) sem trocar o usuário logado.
  Future<bool> authorizeOnce(AppUser u, String pin, Perm p) async =>
      u.active && u.can(p) && await checkPin(u, pin);
}

/// Resultado da análise de impacto.
class ModuleImpact {
  const ModuleImpact(this.blocks, this.notes);
  final List<String> blocks;
  final List<String> notes;
}

/// Sessão Master aberta com a resposta assinada do fornecedor.
class MasterSession {
  MasterSession._(this.valid);
  final bool valid;
}
