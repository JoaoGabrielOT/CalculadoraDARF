import 'package:web/web.dart' as web;

import '../../nucleo/armazenamento_chave_valor.dart';

/// [ChaveValor] sobre o `window.localStorage`.
class ChaveValorNavegador implements ChaveValor {
  web.Storage get _s => web.window.localStorage;

  @override
  String? obter(String chave) => _s.getItem(chave);

  @override
  void definir(String chave, String valor) => _s.setItem(chave, valor);

  @override
  void remover(String chave) => _s.removeItem(chave);

  @override
  Iterable<String> chaves() =>
      [for (var i = 0; i < _s.length; i++) _s.key(i)!];
}

/// O `localStorage`, ou `null` se não existir, não puder ser acessado ou
/// recusar uma gravação de teste (modo privado, dados bloqueados).
ChaveValor? chaveValorDoNavegador() {
  try {
    final kv = ChaveValorNavegador();
    kv.definir('darf:__teste', '1');
    kv.remover('darf:__teste');
    return kv;
  } catch (_) {
    return null;
  }
}
