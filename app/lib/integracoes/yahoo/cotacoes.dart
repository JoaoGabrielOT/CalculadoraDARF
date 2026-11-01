// Cache das cotações dos ativos em carteira (`Cotacoes`, mercado.py:469-509).

import '../../nucleo/ambiente.dart';
import '../../nucleo/compat/ordenacao.dart';

class CacheCotacoes {
  CacheCotacoes(this._cotacao);

  static const validade = 60;

  final Future<double> Function(String ticker) _cotacao;

  /// ticker -> (preço ou nulo, hora da última tentativa).
  final _precos = <String, (double?, double)>{};
  bool _rodando = false;

  bool get rodando => _rodando;

  double? preco(String ticker) => _precos[ticker]?.$1;

  /// Tickers sem preço ou vencidos há mais de [validade] s, em ordem alfabética.
  List<String> pendentes(Iterable<String> tickers) {
    final agora = ambiente.agora();
    return ordenadoPor([
      for (final t in tickers.toSet())
        if (!_precos.containsKey(t) || agora - _precos[t]!.$2 > validade) t,
    ], (t) => [t]);
  }

  /// Busca as cotações vencidas, uma a uma. Devolve `false` na hora se nada
  /// venceu ou se já está rodando; senão `true` ao terminar. Quando a consulta
  /// falha, o preço anterior fica.
  Future<bool> atualizar(Iterable<String> tickers) async {
    final faltam = pendentes(tickers);
    if (faltam.isEmpty || _rodando) return false;
    _rodando = true;
    try {
      for (final t in faltam) {
        double? p;
        try {
          p = await _cotacao(t);
        } catch (_) {
          p = preco(t);
        }
        _precos[t] = (p, ambiente.agora());
      }
    } finally {
      _rodando = false;
    }
    return true;
  }
}
