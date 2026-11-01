import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o barril compila com um símbolo de cada arquivo público e a lista não perde nenhum', () {
    final simbolos = <Object>[
      ClienteHttp,
      ServicoYahoo,
      CacheCotacoes,
      Grafico,
      SessaoGoogle,
      loginNavegador,
      PlanilhaGoogle,
      Google,
      Sincronizador,
      DadosSincronizacaoLocal,
      ServicoNoticias,
      lerRss,
      unescapeHtml,
      Logos,
      baixarImagemNoticia,
      CacheBinarioArquivos,
      verificarAtualizacao,
      executarEmIsolate,
      carregarClienteOAuth,
    ];
    expect(simbolos, hasLength(19));
  });
}
