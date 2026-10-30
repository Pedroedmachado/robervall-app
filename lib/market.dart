/// Busca de peças no Mercado Livre a partir do que foi cadastrado no app
/// (peça, posição, montadora, modelo, motor, versão, ano e código OEM).
library;

import 'models.dart';

/// Um pedaço da busca, que a pessoa pode ligar/desligar.
class SearchTerm {
  SearchTerm(this.key, this.label, this.value, {this.on = true});
  final String key;
  final String label;
  final String value;
  bool on;
}

/// Palavras do modelo que não ajudam a achar a peça (combustível, portas…).
const _filler = {
  'total', 'flex', 'mi', 'mpi', 'gasolina', 'alcool', 'álcool', 'diesel',
  '2p', '3p', '4p', '5p', 'aut', 'aut.', 'mec', 'mec.', 'manual',
  'automatico', 'automático', 'cvt', 'tiptronic', 'fuel', 'power',
};

final _engineRe = RegExp(r'^(\d[.,]\d|\d{1,2}v|turbo|tsi|tce|thp|gdi|v6|v8)$', caseSensitive: false);

/// Divide o modelo do carro em modelo, motor e versão.
/// "Gol 1.0 Mi Total Flex 8V 4p" → (Gol, 1.0 8V, —);
/// "Onix Hatch 1.0 Turbo LTZ" → (Onix Hatch, 1.0 Turbo, LTZ).
(String model, String engine, String version) splitModel(String model) {
  final words = model.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final base = <String>[], engine = <String>[], version = <String>[];
  var seenEngine = false;
  for (final w in words) {
    final low = w.toLowerCase();
    if (_engineRe.hasMatch(low)) {
      seenEngine = true;
      engine.add(w.replaceAll(',', '.'));
    } else if (_filler.contains(low)) {
      continue;
    } else if (!seenEngine) {
      base.add(w);
    } else {
      version.add(w);
    }
  }
  return (base.join(' '), engine.join(' '), version.join(' '));
}

/// Termos da busca, já preenchidos com o carro do sinistro e a peça.
List<SearchTerm> marketTerms(BudgetItem it, Vehicle v) {
  final (model, engine, version) = splitModel(v.model);
  final year = RegExp(r'\d{4}').firstMatch(v.year)?[0] ?? '';
  final origin = switch (it.origin) {
    PartOrigin.original || PartOrigin.genuina => 'original',
    _ => '',
  };
  return [
    SearchTerm('peca', 'Peça', it.description.trim()),
    if (v.brand.trim().isNotEmpty) SearchTerm('marca', 'Montadora', v.brand.trim()),
    if (model.isNotEmpty) SearchTerm('modelo', 'Modelo', model),
    if (engine.isNotEmpty) SearchTerm('motor', 'Motor', engine),
    if (version.isNotEmpty) SearchTerm('versao', 'Versão', version),
    if (year.isNotEmpty) SearchTerm('ano', 'Ano', year),
    if (origin.isNotEmpty) SearchTerm('origem', 'Tipo', origin),
  ].where((t) => t.value.isNotEmpty).toList();
}

String marketQuery(List<SearchTerm> terms) =>
    terms.where((t) => t.on).map((t) => t.value).join(' ');

/// Endereço da lista do Mercado Livre para o texto buscado.
Uri marketUri(String query) {
  final words = query
      .toLowerCase()
      .replaceAll(RegExp(r'[^\wÀ-ÿ.\- ]'), ' ')
      .split(RegExp(r'[\s\-]+'))
      .where((w) => w.isNotEmpty && w != '.')
      .map(Uri.encodeComponent)
      .toList();
  return Uri.parse('https://lista.mercadolivre.com.br/${words.join('-')}');
}
