import 'dart:async';

import 'app/apoio/fontes.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await carregarFontesDeTeste();
  await testMain();
}
