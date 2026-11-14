import 'dart:async';

/// Substitui o test/flutter_test_config.dart nesta pasta: o de lá carrega as
/// fontes com dart:io, que não compila para o navegador (--platform chrome).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
