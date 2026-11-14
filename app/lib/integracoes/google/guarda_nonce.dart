export 'guarda_nonce_memoria.dart'
    if (dart.library.js_interop) 'guarda_nonce_navegador.dart';

/// Guarda o nonce do login na Web entre a ida ao servidor e a volta.
abstract interface class GuardaNonce {
  void guardar(String n);

  /// Devolve o nonce guardado e o apaga.
  String? consumir();
}

/// [GuardaNonce] em memória (testes e plataformas sem navegador).
class GuardaNonceMemoria implements GuardaNonce {
  String? _n;

  @override
  void guardar(String n) => _n = n;

  @override
  String? consumir() {
    final n = _n;
    _n = null;
    return n;
  }
}
