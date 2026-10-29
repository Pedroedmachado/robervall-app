import 'package:flutter_test/flutter_test.dart';
import 'package:funilar/complements.dart';
import 'package:funilar/models.dart';

void main() {
  test('reconhece a peça pelo nome', () {
    expect(groupFor('Porta dianteira esquerda')?.id, 'porta_d');
    expect(groupFor('PORTA TRASEIRA DIREITA')?.id, 'porta_t');
    expect(groupFor('Tampa traseira')?.id, 'tampa');
    expect(groupFor('Porta-malas')?.id, 'tampa');
    expect(groupFor('Para-choque traseiro')?.id, 'pc_t');
    expect(groupFor('Parachoque dianteiro')?.id, 'pc_d');
    expect(groupFor('Para-lama dianteiro direito')?.id, 'paralama');
    expect(groupFor('Capô')?.id, 'capo');
    expect(groupFor('Lateral traseira esquerda')?.id, 'lateral');
    expect(groupFor('Farol esquerdo')?.id, 'farol');
    expect(groupFor('Farol de neblina'), isNull);
    expect(groupFor('Para-brisa')?.id, 'parabrisa');
    expect(groupFor('Alinhamento'), isNull);
  });

  test('troca da porta traz vidro, máquina, forro, chicote, canaleta', () {
    final porta = BudgetItem(description: 'Porta dianteira esquerda', op: ItemOp.troca);
    final list = complementsFor(porta);
    final names = list.map((e) => e.$1.name).toList();
    for (final n in [
      'Vidro da porta',
      'Máquina de vidro',
      'Forro da porta',
      'Chicote elétrico da porta',
      'Canaleta do vidro',
      'Fechadura da porta',
      'Retrovisor externo',
    ]) {
      expect(names, contains(n));
    }
    expect(list.every((e) => e.$2), isTrue); // na troca vêm todos marcados
    final vidro = list.firstWhere((e) => e.$1.name == 'Vidro da porta').$1;
    expect(vidro.laborType, LaborType.vidracaria);
    final item = vidro.toItem(porta.id);
    expect(item.parentId, porta.id);
    expect(item.removeInstall, isTrue);
    expect(opCode(item.op, item.laborHours, item.paintHours,
        removeInstall: item.removeInstall), 'R&I');
  });

  test('pintura marca só o que precisa sair para pintar', () {
    final porta = BudgetItem(
        description: 'Porta dianteira esquerda', op: ItemOp.pintura, paintHours: 3);
    final marked = complementsFor(porta).where((e) => e.$2).map((e) => e.$1.name);
    expect(marked, containsAll(['Maçaneta externa', 'Retrovisor externo', 'Forro da porta']));
    expect(marked, isNot(contains('Vidro da porta')));
  });

  test('complementos ficam logo abaixo da peça e não são juntados', () {
    final a = BudgetItem(description: 'Porta dianteira esquerda', op: ItemOp.troca);
    final b = BudgetItem(description: 'Porta dianteira direita', op: ItemOp.troca);
    final fa = BudgetItem(description: 'Forro da porta', parentId: a.id, laborHours: 0.5, removeInstall: true);
    final fb = BudgetItem(description: 'Forro da porta', parentId: b.id, laborHours: 0.5, removeInstall: true);
    final orphan = BudgetItem(description: 'Vidro', parentId: 'sumiu');
    final grouped = groupChildren([fb, a, b, fa, orphan]);
    expect(grouped.map((e) => e.description).toList(), [
      'Porta dianteira esquerda',
      'Forro da porta',
      'Porta dianteira direita',
      'Forro da porta',
      'Vidro',
    ]);
    expect(grouped[1].parentId, a.id);
    expect(grouped[3].parentId, b.id);
    expect(orphan.parentId, isEmpty);
    expect(mergePartLines(grouped).length, 5);
    expect(BudgetItem.fromJson(fa.toJson()).parentId, a.id);
  });
}
