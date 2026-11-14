import 'package:web/web.dart' as web;

import 'guarda_nonce.dart';

const _chave = 'darf:nonce';

/// [GuardaNonce] sobre o `sessionStorage`: sobrevive à ida ao Google e à
/// volta na mesma aba. `guardar` lança se o armazenamento recusar.
class _GuardaNonceSessao implements GuardaNonce {
  web.Storage get _s => web.window.sessionStorage;

  @override
  void guardar(String n) => _s.setItem(_chave, n);

  @override
  String? consumir() {
    try {
      final n = _s.getItem(_chave);
      _s.removeItem(_chave);
      return n;
    } catch (_) {
      return null;
    }
  }
}

GuardaNonce guardaNonceDoNavegador() => _GuardaNonceSessao();
