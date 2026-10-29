/// Formatação no padrão brasileiro, sem depender de inicialização de locale.

/// Modo produção (chão de fábrica): nenhum valor em R\$ aparece na tela.
bool hideMoney = false;

String money(double v) {
  if (hideMoney) return 'R\$ •••';
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final intPart = cents ~/ 100;
  final dec = (cents % 100).toString().padLeft(2, '0');
  final s = intPart.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}R\$ $buf,$dec';
}

String num2(double v, {int decimals = 2}) {
  var s = v.toStringAsFixed(decimals);
  if (decimals > 0) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s.replaceAll('.', ',');
}

String pct(double v) => '${num2(v, decimals: 1)}%';

String _two(int n) => n.toString().padLeft(2, '0');

String date(DateTime? d) =>
    d == null ? '—' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

String dateTime(DateTime? d) =>
    d == null ? '—' : '${date(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// Converte texto digitado ("1.234,56", "1234.56", "R$ 10") em número.
double parseNum(String text) {
  var t = text.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (t.isEmpty) return 0;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(t) ?? 0;
}

/// Texto para campos de edição de números (vazio quando zero).
String numField(double v) => v == 0 ? '' : num2(v);

String plateMask(String raw) {
  final t = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (t.length > 3) return '${t.substring(0, 3)}-${t.substring(3)}';
  return t;
}
