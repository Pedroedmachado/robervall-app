import 'dart:async';

import 'package:funilar/edition.dart';

/// Os testes do motor compartilhado rodam com tudo ligado (Funilar completo),
/// em qualquer um dos sistemas. O teste de cada sistema está em
/// edicao_test.dart.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  edition = Edition.completo;
  await testMain();
}
