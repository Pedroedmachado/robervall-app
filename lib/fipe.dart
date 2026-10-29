import 'dart:convert';

import 'package:http/http.dart' as http;

import 'modules.dart';

import 'format.dart';

/// Consulta pública da Tabela FIPE (marca, modelo, ano e valor).
class FipeOption {
  final String code;
  final String name;
  const FipeOption(this.code, this.name);
}

class FipeResult {
  final String brand;
  final String model;
  final String year;
  final String fuel;
  final String fipeCode;
  final String reference;
  final double value;

  const FipeResult({
    required this.brand,
    required this.model,
    required this.year,
    required this.fuel,
    required this.fipeCode,
    required this.reference,
    required this.value,
  });
}

enum FipeKind {
  carros('Carros'),
  motos('Motos'),
  caminhoes('Caminhões');

  const FipeKind(this.label);
  final String label;
}

class FipeClient {
  static const _base = 'https://parallelum.com.br/fipe/api/v1';
  final _cache = <String, Object?>{};

  Future<Object?> _get(String path) async {
    gate.require(Mod.integracoes); // módulo desligado: nenhum acesso à internet
    if (_cache.containsKey(path)) return _cache[path];
    final r = await http
        .get(Uri.parse('$_base/$path'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('FIPE respondeu ${r.statusCode}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    _cache[path] = j;
    return j;
  }

  List<FipeOption> _opts(Object? list) => list is List
      ? list
          .whereType<Map>()
          .map((e) => FipeOption('${e['codigo']}', '${e['nome']}'))
          .toList()
      : <FipeOption>[];

  Future<List<FipeOption>> brands(FipeKind k) async =>
      _opts(await _get('${k.name}/marcas'));

  Future<List<FipeOption>> models(FipeKind k, String brand) async {
    final j = await _get('${k.name}/marcas/$brand/modelos');
    return j is Map ? _opts(j['modelos']) : <FipeOption>[];
  }

  Future<List<FipeOption>> years(FipeKind k, String brand, String model) async =>
      _opts(await _get('${k.name}/marcas/$brand/modelos/$model/anos'));

  Future<FipeResult> price(
      FipeKind k, String brand, String model, String year) async {
    final j = await _get('${k.name}/marcas/$brand/modelos/$model/anos/$year');
    if (j is! Map) throw Exception('Resposta inválida da FIPE');
    final ano = '${j['AnoModelo'] ?? ''}';
    return FipeResult(
      brand: '${j['Marca'] ?? ''}',
      model: '${j['Modelo'] ?? ''}',
      year: ano == '32000' ? '0 km' : ano,
      fuel: '${j['Combustivel'] ?? ''}',
      fipeCode: '${j['CodigoFipe'] ?? ''}',
      reference: '${j['MesReferencia'] ?? ''}'.trim(),
      value: parseNum('${j['Valor'] ?? ''}'),
    );
  }
}

final fipe = FipeClient();
