import 'package:calculadoradarf/integracoes/integracoes.dart';

import '../../integracoes/apoio/cliente_falso.dart';

/// Serviço do Yahoo sobre um [ClienteFalso]: mesma configuração de
/// `ServicoYahoo.clientePadrao`, sem dormir de verdade e sem isolate.
ServicoYahoo yahooFalso(ClienteFalso falso) => ServicoYahoo(
  ClienteHttp(
    falso,
    userAgent: 'Mozilla/5.0',
    maxSimultaneas: 3,
    esperar: (_) async {},
  ),
  executar: executarDireto,
);

/// Yahoo que nunca deveria ser consultado (testes sem mercado).
ServicoYahoo yahooSemRede() => yahooFalso(
  ClienteFalso((_) => throw StateError('o teste não deveria usar a rede')),
);

/// Corpo do chart com [n] pregões diários e o preço da meta em [preco].
String corpoChart({
  int n = 20,
  String preco = '10.5',
  String nome = 'Petrobras',
}) {
  final ts = [for (var i = 0; i < n; i++) 1760000000 + i * 86400];
  final altas = [for (var i = 0; i < n; i++) 11.0 + i * 0.1];
  final baixas = [for (var i = 0; i < n; i++) 9.0 + i * 0.1];
  final fech = [for (var i = 0; i < n; i++) 10.0 + i * 0.1];
  return '{"chart": {"result": [{"meta": {"regularMarketPrice": $preco, '
      '"gmtoffset": -10800, "longName": "$nome"}, '
      '"timestamp": $ts, "indicators": {"quote": [{"high": $altas, '
      '"low": $baixas, "close": $fech}]}}]}}';
}
