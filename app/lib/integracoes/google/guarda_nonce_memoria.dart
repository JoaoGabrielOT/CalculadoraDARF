import 'guarda_nonce.dart';

final _guarda = GuardaNonceMemoria();

/// Fora do navegador não há login pelo servidor: guarda só em memória.
GuardaNonce guardaNonceDoNavegador() => _guarda;
