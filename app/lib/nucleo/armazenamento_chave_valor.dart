import 'armazenamento.dart';

/// Texto mostrado quando o navegador não tem mais espaço.
const textoArmazenamentoCheio =
    'O navegador ficou sem espaço para os dados do app. '
    'Os dados já sincronizados continuam na planilha do Google.';

/// Arquivos que podem ser refeitos e portanto são apagados quando falta espaço.
const arquivosDescartaveis = ['noticias_detalhes.json', 'noticias.json'];

class ErroArmazenamentoCheio implements Exception {
  @override
  String toString() => textoArmazenamentoCheio;
}

/// Mapa de texto em texto, como o `localStorage` do navegador.
abstract interface class ChaveValor {
  String? obter(String chave);
  void definir(String chave, String valor);
  void remover(String chave);
  Iterable<String> chaves();
}

/// [ChaveValor] em memória, para testes.
class ChaveValorMemoria implements ChaveValor {
  final Map<String, String> _dados = {};

  @override
  String? obter(String chave) => _dados[chave];

  @override
  void definir(String chave, String valor) => _dados[chave] = valor;

  @override
  void remover(String chave) => _dados.remove(chave);

  @override
  Iterable<String> chaves() => _dados.keys.toList();
}

/// [Armazenamento] sobre um [ChaveValor], com as chaves prefixadas.
class ArmazenamentoChaveValor implements Armazenamento {
  ArmazenamentoChaveValor(this._kv, {this.prefixo = 'darf:'});

  final ChaveValor _kv;
  final String prefixo;

  @override
  String? ler(String nome) => _kv.obter('$prefixo$nome');

  @override
  void gravar(String nome, String conteudo) {
    try {
      _kv.definir('$prefixo$nome', conteudo);
    } catch (_) {
      for (final d in arquivosDescartaveis.where((d) => d != nome)) {
        _kv.remover('$prefixo$d');
      }
      try {
        _kv.definir('$prefixo$nome', conteudo);
      } catch (_) {
        throw ErroArmazenamentoCheio();
      }
    }
  }

  @override
  bool existe(String nome) => ler(nome) != null;

  @override
  List<String> listar() => [
        for (final c in _kv.chaves())
          if (c.startsWith(prefixo)) c.substring(prefixo.length),
      ];

  @override
  void apagar(String nome) => _kv.remover('$prefixo$nome');
}
