import 'dart:convert';

import '../executor.dart';

/// Até este tamanho o JSON é decodificado na hora; acima, fora da thread da interface.
const limiteJsonDireto = 64 * 1024;

Object? _decodificar(List<int> corpo) => jsonDecode(utf8.decode(corpo));

/// UTF-8 + `jsonDecode` (preserva int e double como o `json.loads`).
Future<Object?> decodificarJson(List<int> corpo, Executar executar) {
  if (corpo.length <= limiteJsonDireto) {
    return Future.value(_decodificar(corpo));
  }
  return executar<Object?>(() => _decodificar(corpo));
}
