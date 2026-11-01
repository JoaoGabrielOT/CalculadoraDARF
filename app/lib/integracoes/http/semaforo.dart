import 'dart:async';
import 'dart:collection';

/// Limita quantas ações rodam ao mesmo tempo; as demais esperam na fila.
class Semaforo {
  Semaforo(this.maximo) : assert(maximo > 0);

  final int maximo;
  final Queue<Completer<void>> _fila = Queue();
  int _emUso = 0;

  /// Vagas ocupadas agora.
  int get emUso => _emUso;

  Future<T> usar<T>(Future<T> Function() acao) async {
    if (_emUso < maximo) {
      _emUso++;
    } else {
      final vez = Completer<void>();
      _fila.add(vez);
      await vez.future;
    }
    try {
      return await acao();
    } finally {
      // A vaga passa direto ao próximo da fila, sem abrir brecha.
      if (_fila.isNotEmpty) {
        _fila.removeFirst().complete();
      } else {
        _emUso--;
      }
    }
  }
}
