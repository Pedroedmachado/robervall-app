// Ferramenta do fornecedor: emite licenças e responde ao acesso Master.
//
//   dart run tool/licenca.dart emitir --cliente "Oficina X" [--documento CNPJ]
//        [--modulos todos|vistoria,financeiro,...] [--validade 2027-12-31]
//        [--aparelho FN-XXXX-XXXX-XXXX] [--id LIC-001] [--saida arquivo.lic]
//   dart run tool/licenca.dart master --desafio M-FN-XXXX-XXXX-XXXX-1A2B3C4D
//   dart run tool/licenca.dart chaves      (gera um par novo)
//
// A chave privada vem da variável FUNILAR_LICENCA_CHAVE (base64 dos 32 bytes)
// ou de --chave caminho/do/arquivo. Ela nunca vai para o app nem para o git.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:funilar/licensing.dart';
import 'package:funilar/modules.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  final cmd = args.first;
  final opt = <String, String>{};
  for (var i = 1; i < args.length - 1; i++) {
    if (args[i].startsWith('--')) opt[args[i].substring(2)] = args[i + 1];
  }

  if (cmd == 'chaves') {
    final seed = List.generate(32, (_) => Random.secure().nextInt(256));
    stdout.writeln('Chave privada (guarde em segredo): ${base64.encode(seed)}');
    stdout.writeln('Chave pública (vai no app):       ${await publicKeyOf(seed)}');
    return;
  }

  final seed = await _seed(opt['chave']);
  final pub = await publicKeyOf(seed);
  if (pub != productionPublicKey) {
    stderr.writeln('Atenção: esta chave não é a oficial do app (pública $pub).');
  }

  switch (cmd) {
    case 'emitir':
      final customer = opt['cliente'] ?? '';
      if (customer.trim().isEmpty) {
        stderr.writeln('Informe --cliente.');
        exit(2);
      }
      final modsArg = (opt['modulos'] ?? 'todos').trim();
      final mods = <Mod>{};
      if (modsArg == 'todos' || modsArg.isEmpty) {
        mods.addAll(Mod.values);
      } else {
        for (final n in modsArg.split(',')) {
          final m = Mod.byName(n.trim());
          if (m == null) {
            stderr.writeln('Módulo desconhecido: $n. Use: ${Mod.values.map((e) => e.name).join(', ')}');
            exit(2);
          }
          mods.add(m);
        }
      }
      // obrigatórios entram junto
      for (final m in [...mods]) {
        mods.addAll(m.requires);
      }
      final lic = License(
        id: (opt['id'] ?? '').isNotEmpty
            ? opt['id']!
            : 'LIC-${DateTime.now().toUtc().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[^0-9]'), '')}',
        customer: customer.trim(),
        document: (opt['documento'] ?? '').trim(),
        modules: mods,
        issued: DateTime.now(),
        expires: (opt['validade'] ?? '').isEmpty ? null : DateTime.parse(opt['validade']!),
        device: (opt['aparelho'] ?? '').trim().toUpperCase(),
      );
      final text = await signLicense(lic, seed);
      if ((opt['saida'] ?? '').isNotEmpty) {
        await File(opt['saida']!).writeAsString(text);
      }
      stdout.write(text);
    case 'master':
      final ch = (opt['desafio'] ?? '').trim();
      if (!ch.startsWith('M-')) {
        stderr.writeln('Informe --desafio (código mostrado na tela Master).');
        exit(2);
      }
      stdout.writeln(await signMasterChallenge(ch, seed));
    default:
      _usage();
  }
}

Future<List<int>> _seed(String? path) async {
  final raw = path != null
      ? (await File(path).readAsString()).trim()
      : (Platform.environment['FUNILAR_LICENCA_CHAVE'] ?? '').trim();
  if (raw.isEmpty) {
    stderr.writeln('Chave privada não informada (FUNILAR_LICENCA_CHAVE ou --chave).');
    exit(2);
  }
  final seed = base64.decode(raw);
  if (seed.length != 32) {
    stderr.writeln('Chave privada inválida.');
    exit(2);
  }
  return seed;
}

void _usage() => stdout.writeln(
    'Uso: dart run tool/licenca.dart emitir|master|chaves [opções] (veja o topo do arquivo)');
