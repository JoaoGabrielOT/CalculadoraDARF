import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o barril exporta um símbolo de cada arquivo público', () {
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
