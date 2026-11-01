/// Tema visual escolhido em Configurações (salvo por aparelho em
/// `Config.extras['tema_visual']`). Puro Dart: roda também no isolate de serviços.
enum TemaVisual {
  automatico('automatico', 'Automático'),
  terminal('terminal', 'Terminal'),
  claro('claro', 'Claro'),
  moderno('moderno', 'Moderno');

  const TemaVisual(this.chave, this.rotulo);

  final String chave;
  final String rotulo;

  /// Chave desconhecida ou ausente vira [automatico].
  static TemaVisual daChave(Object? chave) {
    for (final t in values) {
      if (t.chave == chave) return t;
    }
    return automatico;
  }
}
