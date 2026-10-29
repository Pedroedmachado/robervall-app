/// Licença assinada (Ed25519), código do aparelho, ativação local dos
/// módulos e hash de PIN. Tudo funciona offline.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'modules.dart';

/// Cabeçalho do texto da licença.
const licenseHeader = 'FUNILAR-LICENCA-1';

/// Chave pública oficial. A chave privada fica só com o fornecedor
/// (segredo do GitHub / arquivo guardado por ele) e nunca entra no app.
const productionPublicKey = 'hm29R9j0zCg/SS7y9A7PlONbsqtURB55c5laM387Hrg=';

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// Conteúdo da licença.
class License {
  final String id;
  final String customer;
  final String document;
  final Set<Mod> modules;
  final DateTime issued;
  final DateTime? expires; // null = sem validade
  final String device; // vazio = qualquer aparelho

  License({
    required this.id,
    required this.customer,
    this.document = '',
    required Set<Mod> modules,
    required this.issued,
    this.expires,
    this.device = '',
  }) : modules = {...modules, Mod.nucleo};

  /// Todos os módulos, sem validade nem aparelho (uso interno/testes).
  factory License.full({String customer = 'Oficina'}) => License(
        id: 'interna',
        customer: customer,
        modules: Mod.values.toSet(),
        issued: DateTime(2026, 1, 1),
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'cliente': customer,
        'documento': document,
        'modulos': [for (final m in Mod.values) if (modules.contains(m)) m.name],
        'emitida': issued.toIso8601String().substring(0, 10),
        'validade': expires?.toIso8601String().substring(0, 10),
        'aparelho': device,
      };

  factory License.fromJson(Map<String, dynamic> j) => License(
        id: '${j['id'] ?? ''}',
        customer: '${j['cliente'] ?? ''}',
        document: '${j['documento'] ?? ''}',
        modules: {
          for (final n in (j['modulos'] as List? ?? const []))
            if (Mod.byName('$n') != null) Mod.byName('$n')!
        },
        issued: DateTime.tryParse('${j['emitida']}') ?? DateTime(2000),
        expires: j['validade'] == null
            ? null
            : DateTime.tryParse('${j['validade']}'),
        device: '${j['aparelho'] ?? ''}',
      );
}

enum LicenseStatus {
  valid('Licença válida'),
  missing('Nenhuma licença instalada'),
  invalid('Licença inválida ou adulterada'),
  expired('Licença vencida'),
  wrongDevice('Licença de outro computador'),
  clockRollback('Data do aparelho foi atrasada');

  const LicenseStatus(this.label);
  final String label;
}

class LicenseCheck {
  const LicenseCheck(this.status, [this.license]);
  final LicenseStatus status;
  final License? license;
  bool get ok => status == LicenseStatus.valid;
}

/// Assina uma licença com a semente (32 bytes) da chave privada.
Future<String> signLicense(License l, List<int> privateSeed) async {
  final payload = utf8.encode(jsonEncode(l.toJson()));
  final algo = Ed25519();
  final kp = await algo.newKeyPairFromSeed(privateSeed);
  final sig = await algo.sign(payload, keyPair: kp);
  return '$licenseHeader\n${_b64(payload)}.${_b64(sig.bytes)}\n';
}

Future<String> publicKeyOf(List<int> privateSeed) async {
  final kp = await Ed25519().newKeyPairFromSeed(privateSeed);
  return base64.encode((await kp.extractPublicKey()).bytes);
}

Future<bool> _verify(List<int> msg, List<int> sig, String publicKey) async {
  try {
    return await Ed25519().verify(msg,
        signature: Signature(sig,
            publicKey: SimplePublicKey(base64.decode(publicKey),
                type: KeyPairType.ed25519)));
  } catch (_) {
    return false;
  }
}

/// Confere assinatura, aparelho, validade e relógio. Aceita o texto colado
/// com quebras de linha ou espaços no meio.
Future<LicenseCheck> verifyLicense(
  String? text, {
  required String deviceId,
  DateTime? now,
  DateTime? lastSeen,
  String publicKey = productionPublicKey,
}) async {
  if (text == null || text.trim().isEmpty) {
    return const LicenseCheck(LicenseStatus.missing);
  }
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  final m = RegExp('${licenseHeader}([A-Za-z0-9_-]+)\\.([A-Za-z0-9_-]+)')
      .firstMatch(compact);
  if (m == null) return const LicenseCheck(LicenseStatus.invalid);
  final Uint8List payload, sig;
  try {
    payload = _unb64(m[1]!);
    sig = _unb64(m[2]!);
  } catch (_) {
    return const LicenseCheck(LicenseStatus.invalid);
  }
  if (sig.length != 64 || !await _verify(payload, sig, publicKey)) {
    return const LicenseCheck(LicenseStatus.invalid);
  }
  final License lic;
  try {
    lic = License.fromJson(
        Map<String, dynamic>.from(jsonDecode(utf8.decode(payload)) as Map));
  } catch (_) {
    return const LicenseCheck(LicenseStatus.invalid);
  }
  final t = now ?? DateTime.now();
  if (lic.device.isNotEmpty && lic.device != deviceId) {
    return LicenseCheck(LicenseStatus.wrongDevice, lic);
  }
  if (lastSeen != null && t.isBefore(lastSeen.subtract(const Duration(days: 1)))) {
    return LicenseCheck(LicenseStatus.clockRollback, lic);
  }
  final exp = lic.expires;
  if (exp != null && t.isAfter(DateTime(exp.year, exp.month, exp.day + 1))) {
    return LicenseCheck(LicenseStatus.expired, lic);
  }
  return LicenseCheck(LicenseStatus.valid, lic);
}

// ------------------------------------------------------------------ Master

/// Desafio para o acesso Master: aparelho + número aleatório (uso único).
String newMasterChallenge(String deviceId, [Random? rnd]) {
  final r = rnd ?? Random.secure();
  final nonce =
      List.generate(4, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
  return 'M-$deviceId-$nonce';
}

/// Resposta do fornecedor: assinatura do desafio com a chave privada.
Future<String> signMasterChallenge(String challenge, List<int> privateSeed) async {
  final algo = Ed25519();
  final kp = await algo.newKeyPairFromSeed(privateSeed);
  final sig = await algo.sign(utf8.encode(challenge.trim()), keyPair: kp);
  return _b64(sig.bytes);
}

Future<bool> verifyMasterResponse(String challenge, String response,
    {String publicKey = productionPublicKey}) async {
  try {
    final sig = _unb64(response.replaceAll(RegExp(r'\s+'), ''));
    if (sig.length != 64) return false;
    return await _verify(utf8.encode(challenge.trim()), sig, publicKey);
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------- aparelho

/// Código do aparelho (ex.: FN-3F2A-91C0-7B4D). Usa o identificador da
/// máquina quando existe (Windows/Linux/macOS); senão um código gerado na
/// instalação e guardado na pasta do app.
Future<String> computeDeviceId(Directory baseDir) async {
  var raw = '';
  try {
    if (Platform.isWindows) {
      final r = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid'
      ]);
      raw = RegExp(r'MachineGuid\s+REG_SZ\s+(\S+)')
              .firstMatch('${r.stdout}')
              ?.group(1) ??
          '';
    } else if (Platform.isLinux) {
      final f = File('/etc/machine-id');
      if (await f.exists()) raw = (await f.readAsString()).trim();
    } else if (Platform.isMacOS) {
      final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      raw = RegExp(r'"IOPlatformUUID" = "([^"]+)"')
              .firstMatch('${r.stdout}')
              ?.group(1) ??
          '';
    }
  } catch (_) {
    raw = '';
  }
  if (raw.isEmpty) {
    final f = File('${baseDir.path}/aparelho.id');
    if (await f.exists()) {
      raw = (await f.readAsString()).trim();
    }
    if (raw.isEmpty) {
      final r = Random.secure();
      raw = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await f.writeAsString(raw, flush: true);
    }
  }
  final h = crypto.sha256.convert(utf8.encode('funilar|$raw')).toString().toUpperCase();
  return 'FN-${h.substring(0, 4)}-${h.substring(4, 8)}-${h.substring(8, 12)}';
}

// ---------------------------------------------------------- ativação local

/// Módulos ligados neste aparelho + histórico. Guardado em modulos.json com
/// uma soma de verificação; nunca liga nada fora da licença.
class Activation {
  Set<Mod> enabled;
  List<Map<String, dynamic>> log;
  DateTime? lastSeen;
  bool tampered;

  Activation({Set<Mod>? enabled, List<Map<String, dynamic>>? log, this.lastSeen, this.tampered = false})
      : enabled = enabled ?? {},
        log = log ?? [];

  static String _check(Map<String, dynamic> body, String deviceId) =>
      crypto.sha256.convert(utf8.encode('${jsonEncode(body)}|$deviceId|funilar')).toString();

  Map<String, dynamic> _body() => {
        'ativos': [for (final m in Mod.values) if (enabled.contains(m)) m.name],
        'historico': log,
        'visto': lastSeen?.toIso8601String(),
      };

  Future<void> save(File f, String deviceId) async {
    final body = _body();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
        jsonEncode({...body, 'check': _check(body, deviceId)}),
        flush: true);
    await tmp.rename(f.path);
  }

  /// null = ainda não existe (primeiro uso).
  static Future<Activation?> load(File f, String deviceId) async {
    if (!await f.exists()) return null;
    try {
      final j = Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
      final a = Activation(
        enabled: {
          for (final n in (j['ativos'] as List? ?? const []))
            if (Mod.byName('$n') != null) Mod.byName('$n')!
        },
        log: [
          for (final e in (j['historico'] as List? ?? const []))
            if (e is Map) Map<String, dynamic>.from(e)
        ],
        lastSeen: DateTime.tryParse('${j['visto']}'),
      );
      if (j['check'] != _check(a._body(), deviceId)) a.tampered = true;
      return a;
    } catch (_) {
      return Activation(tampered: true);
    }
  }
}

// ---------------------------------------------------------------- PIN

/// Hash do PIN com PBKDF2-HMAC-SHA256 e sal aleatório.
Future<(String hash, String salt)> hashPin(String pin, {String? salt}) async {
  final s = salt ??
      base64.encode(List.generate(16, (_) => Random.secure().nextInt(256)));
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 20000,
    bits: 256,
  ).deriveKeyFromPassword(password: pin, nonce: base64.decode(s));
  return (base64.encode(await key.extractBytes()), s);
}

Future<bool> checkPin(AppUser u, String pin) async {
  if (u.pinHash.isEmpty) return pin.isEmpty;
  final (h, _) = await hashPin(pin, salt: u.salt);
  return h == u.pinHash;
}
