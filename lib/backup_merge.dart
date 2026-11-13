// Importar backup sem apagar o que já existe: cada registro do arquivo é
// comparado com os deste aparelho. O que já existe (mesmo registro ou um
// igual cadastrado de novo) é atualizado; o que é novo é acrescentado.
//
// Trabalha direto no JSON (dados.json), então vale para todos os cadastros.

import 'dart:convert';

/// Quanto foi acrescentado / atualizado em cada parte do sistema.
class MergeReport {
  final Map<String, int> added = {};
  final Map<String, int> updated = {};
  final Map<String, int> same = {};

  /// Backup aberto num aparelho vazio: virou cópia do arquivo.
  bool fullRestore = false;

  /// Usuários que só existiam no backup (entraram desativados).
  int inactiveUsers = 0;

  int get totalAdded => added.values.fold(0, (a, b) => a + b);
  int get totalUpdated => updated.values.fold(0, (a, b) => a + b);

  static const labels = {
    'claims': 'orçamentos',
    'contacts': 'cadastros',
    'catalog': 'itens do catálogo',
    'entries': 'lançamentos do Financeiro',
    'stock': 'itens do estoque',
    'users': 'usuários',
    'cash': 'lançamentos do caixa',
    'docs': 'documentos',
  };

  /// "3 orçamentos novos, 12 itens do estoque atualizados…"
  String summary() {
    if (fullRestore) return 'Backup restaurado neste aparelho.';
    final parts = <String>[];
    for (final k in labels.keys) {
      final a = added[k] ?? 0, u = updated[k] ?? 0;
      if (a == 0 && u == 0) continue;
      parts.add([
        if (a > 0) '$a ${labels[k]} ${a == 1 ? 'novo' : 'novos'}',
        if (u > 0) '$u ${a > 0 ? '' : '${labels[k]} '}${u == 1 ? 'atualizado' : 'atualizados'}',
      ].join(' e ').replaceAll('  ', ' '));
    }
    if (parts.isEmpty) return 'Nada mudou: tudo do backup já estava neste aparelho.';
    final users = inactiveUsers == 0
        ? ''
        : ' ${inactiveUsers == 1 ? 'O usuário novo entrou desativado' : 'Os usuários novos entraram desativados'} (ative em Ajustes › Usuários).';
    return 'Mesclado: ${parts.join(' · ')}.$users';
  }
}

typedef _J = Map<String, dynamic>;

String _n(Object? v) => '${v ?? ''}'
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

String _day(Object? v) {
  final d = DateTime.tryParse('${v ?? ''}');
  return d == null ? '' : '${d.year}-${d.month}-${d.day}';
}

String _money(Object? v) => v is num ? v.toStringAsFixed(2) : _n(v);

/// Chaves que reconhecem "o mesmo registro cadastrado de novo" (ids
/// diferentes). Vazio = sem chave (só o id vale).
List<String> _keys(String col, _J j) {
  String k(List<Object?> parts) =>
      parts.any((p) => '$p'.isEmpty) ? '' : parts.join('|');
  switch (col) {
    case 'claims':
      final v = j['vehicle'] is Map ? j['vehicle'] as Map : const {};
      return [
        k([_n(j['claimNumber']), _n(j['insurerName'])]),
        k([_n(j['number']), _n(v['plate'])]),
      ];
    case 'contacts':
      return [k([_n(j['kind']), _n(j['name'])])];
    case 'catalog':
      return [k([_n(j['description']), _n(j['partNumber']), _n(j['op'])])];
    case 'entries':
      return [
        k([
          '${j['isIncome']}',
          _day(j['date']),
          _money(j['amount']),
          _n(j['description']),
        ])
      ];
    case 'cash':
      return [
        k(['${j['in']}', _day(j['date']), _money(j['amount']), _n(j['description'])])
      ];
    case 'stock':
      return [
        k([_n(j['kind']), _n(j['partNumber'])]),
        k([_n(j['kind']), _n(j['name'])]),
      ];
    case 'users':
      return [k([_n(j['name'])])];
    case 'docs':
      return [
        k([_n(j['kind']), _n(j['party']), _n(j['number'])]),
        if (_n(j['number']).isEmpty)
          k([_n(j['kind']), _n(j['party']), _day(j['date']), _money(j['total'])]),
      ];
  }
  return const [];
}

bool _empty(Object? v) =>
    v == null ||
    (v is String && v.trim().isEmpty) ||
    (v is List && v.isEmpty) ||
    (v is Map && v.isEmpty);

/// O registro do backup atualiza o deste aparelho, sem apagar com campo
/// vazio o que já estava preenchido. Se o daqui foi alterado depois
/// (updatedAt mais novo), fica o daqui.
(_J, bool) _overlay(String col, _J mine, _J theirs) {
  final a = DateTime.tryParse('${mine['updatedAt'] ?? ''}');
  final b = DateTime.tryParse('${theirs['updatedAt'] ?? ''}');
  // alterado aqui depois do backup: os dados daqui ficam
  final mineNewer = a != null && b != null && a.isAfter(b);
  final out = Map<String, dynamic>.from(mine);
  theirs.forEach((k, v) {
    if (k == 'id') return;
    // históricos e fotos: junta os dois, sem repetir (mesmo quando o
    // registro daqui é o mais novo)
    if (_unionKeys.contains(k) && v is List) {
      final seen = <String>{};
      out[k] = [
        for (final e in [...(mine[k] is List ? mine[k] as List : const []), ...v])
          if (seen.add(e is Map && e['id'] != null ? 'id:${e['id']}' : jsonEncode(e))) e
      ];
      return;
    }
    if (mineNewer) return;
    if (_empty(v) && !_empty(mine[k])) return;
    // o número do orçamento daqui não muda
    if (col == 'claims' && k == 'number' && !_empty(mine[k])) return;
    // peças baixadas do estoque: resolvido depois, item a item (_mergeTaken)
    if (col == 'claims' && k == 'stockTaken') return;
    // usuário que já existe aqui: papel, senha e ativo/inativo são os daqui
    // (um backup não promove ninguém a administrador nem tranca o app)
    if (col == 'users') return;
    out[k] = v;
  });
  return (out, mineNewer);
}

const _unionKeys = {'timeline', 'photos', 'ins'};

/// Peças que o orçamento já baixou do estoque ("stockTaken"). A baixa tem de
/// combinar com o saldo que ficou valendo em cada item: se o saldo é o deste
/// aparelho, vale a baixa registrada aqui; se veio do backup, vale a do
/// backup. (O app ainda acerta estoque × orçamentos depois da mescla.)
void _mergeTaken(_J claim, Object? mineTaken, Object? theirTaken, Set<String> localStock) {
  final out = <String, dynamic>{};
  if (mineTaken is Map) {
    mineTaken.forEach((k, v) {
      if (v is Map && localStock.contains('${v['s']}')) out['$k'] = v;
    });
  }
  if (theirTaken is Map) {
    theirTaken.forEach((k, v) {
      if (v is Map && !localStock.contains('${v['s']}')) out['$k'] = v;
    });
  }
  if (out.isEmpty) {
    claim.remove('stockTaken');
  } else {
    claim['stockTaken'] = out;
  }
}

/// Troca os ids do backup pelos ids daqui (registros reconhecidos como o
/// mesmo), em todo o JSON — assim as ligações (orçamento ↔ lançamento,
/// nota ↔ estoque…) continuam certas.
Object? _remap(Object? v, Map<String, String> ids) {
  if (ids.isEmpty) return v;
  if (v is String) {
    final direct = ids[v];
    if (direct != null) return direct;
    // ids montados a partir de outros ("lucro-<orçamento>",
    // "equipe-<orçamento>-<funcionário>")
    if (v.contains('-') && v.length < 80 && !v.contains(' ')) {
      final parts = v.split('-');
      if (parts.any(ids.containsKey)) return parts.map((p) => ids[p] ?? p).join('-');
    }
    return v;
  }
  if (v is List) return [for (final e in v) _remap(e, ids)];
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) (ids['${e.key}'] ?? '${e.key}'): _remap(e.value, ids)
    };
  }
  return v;
}

List<_J> _list(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <_J>[];

bool _isEmptyData(_J j) =>
    ['claims', 'entries', 'stock', 'cash', 'docs'].every((k) => _list(j[k]).isEmpty) &&
    _list(j['contacts']).isEmpty;

/// Junta o backup ([theirs]) com os dados deste aparelho ([mine]).
(_J, MergeReport) mergeBackupJson(_J mine, _J theirs) {
  final report = MergeReport();
  if (_isEmptyData(mine)) {
    // aparelho sem nada: o backup vem inteiro (com os ajustes dele)
    report.fullRestore = true;
    for (final c in MergeReport.labels.keys) {
      report.added[c] = _list(theirs[c]).length;
    }
    final out = Map<String, dynamic>.from(theirs);
    // com usuários já criados neste aparelho, valem os daqui (papel e
    // senha); os do backup só entram num aparelho sem nenhum usuário
    final mineUsers = _list(mine['users']);
    if (mineUsers.isNotEmpty) {
      final users = [...mineUsers];
      for (final u in _list(theirs['users'])) {
        if (users.every((x) => x['id'] != u['id'] && _n(x['name']) != _n(u['name']))) {
          users.add(u..['active'] = false);
          report.inactiveUsers++;
        }
      }
      out['users'] = users;
    }
    return (out, report);
  }

  // 1) quem do backup já existe aqui (por id ou pela chave natural)
  final ids = <String, String>{};
  final matchOf = <String, Map<int, int>>{}; // coleção → índice backup → índice daqui
  for (final col in MergeReport.labels.keys) {
    final here = _list(mine[col]);
    final there = _list(theirs[col]);
    final byId = <String, int>{};
    final byKey = <String, int>{};
    for (final (i, r) in here.indexed) {
      final id = '${r['id'] ?? ''}';
      if (id.isNotEmpty) byId[id] = i;
      for (final k in _keys(col, r)) {
        if (k.isNotEmpty) byKey.putIfAbsent(k, () => i);
      }
    }
    final used = <int>{};
    final m = <int, int>{};
    // primeiro quem é o mesmo registro (mesmo id)…
    for (final (i, r) in there.indexed) {
      final hit = byId['${r['id'] ?? ''}'];
      if (hit == null || used.contains(hit)) continue;
      used.add(hit);
      m[i] = hit;
    }
    // …depois, entre os que sobraram, quem foi cadastrado de novo (mesmo
    // nome/número). Assim um parecido não toma o lugar do registro certo.
    for (final (i, r) in there.indexed) {
      if (m.containsKey(i)) continue;
      final id = '${r['id'] ?? ''}';
      if (byId.containsKey(id)) continue; // o dono desse id já foi casado
      for (final k in _keys(col, r)) {
        if (k.isEmpty) continue;
        final h = byKey[k];
        if (h == null || used.contains(h)) continue;
        used.add(h);
        m[i] = h;
        final hereId = '${here[h]['id'] ?? ''}';
        if (id.isNotEmpty && hereId.isNotEmpty && id != hereId) ids[id] = hereId;
        break;
      }
    }
    matchOf[col] = m;
  }

  // 2) ligações do backup passam a apontar para os ids daqui
  final t = _remap(theirs, ids) as _J;

  // 3) atualiza o que existe, acrescenta o que é novo. O estoque vai
  // primeiro: a baixa de peças de cada orçamento depende de qual aparelho
  // ficou com o saldo de cada item.
  final out = Map<String, dynamic>.from(mine);
  final localStock = <String>{}; // itens cujo saldo que vale é o daqui
  final matchedStock = matchOf['stock']!.values.toSet();
  for (final (i, r) in _list(mine['stock']).indexed) {
    if (!matchedStock.contains(i)) localStock.add('${r['id']}'); // só existe aqui
  }
  for (final col in ['stock', ...MergeReport.labels.keys.where((c) => c != 'stock')]) {
    final here = _list(mine[col]);
    final there = _list(t[col]);
    final m = matchOf[col]!;
    var add = 0, upd = 0, same = 0;
    final appended = <_J>[];
    for (final (i, r) in there.indexed) {
      final h = m[i];
      if (h == null) {
        // usuário que só existe no backup entra desativado: quem administra
        // este aparelho decide se ativa (Ajustes › Usuários)
        if (col == 'users') {
          r['active'] = false;
          report.inactiveUsers++;
        }
        if (col == 'claims') _mergeTaken(r, null, r['stockTaken'], localStock);
        appended.add(r);
        add++;
        continue;
      }
      final (merged, mineNewer) = _overlay(col, here[h], r);
      if (col == 'stock' && mineNewer) {
        localStock.add('${here[h]['id']}'); // saldo daqui é o mais novo
      }
      if (col == 'claims') {
        _mergeTaken(merged, here[h]['stockTaken'], r['stockTaken'], localStock);
      }
      if (jsonEncode(merged) == jsonEncode(here[h])) {
        same++;
      } else {
        here[h] = merged;
        upd++;
      }
    }
    out[col] = [...here, ...appended];
    report.added[col] = add;
    report.updated[col] = upd;
    report.same[col] = same;
  }

  // ajustes: ficam os daqui; o que estiver em branco aqui vem do backup
  final s = Map<String, dynamic>.from(mine['settings'] is Map ? mine['settings'] as Map : {});
  final ts = t['settings'] is Map ? t['settings'] as Map : const {};
  ts.forEach((k, v) {
    if (_empty(s[k]) && !_empty(v)) s['$k'] = v;
  });
  final nm = s['nextNumber'], nt = ts['nextNumber'];
  if (nm is num && nt is num && nt > nm) s['nextNumber'] = nt;
  out['settings'] = s;

  // outras partes do arquivo que este aparelho ainda não tem
  t.forEach((k, v) {
    if (!out.containsKey(k)) out[k] = v;
  });
  return (out, report);
}
