// Conversão de valor em célula da API do Sheets e normalização da leitura
// (google_sync.py:76-83, 427-441).

import '../compat/conversao.dart';
import 'abas.dart';

/// Linha de uma aba: texto, número ou nulo em cada coluna.
typedef Linha = List<Object?>;

/// `celula(v)`: vazio, texto ("Sim"/"Não" para booleano) ou número.
Map<String, Object?> celula(Object? v) {
  if (v == null || v == '') return <String, Object?>{};
  if (v is bool) {
    return {
      'userEnteredValue': {'stringValue': v ? 'Sim' : 'Não'},
    };
  }
  if (v is num) {
    return {
      'userEnteredValue': {'numberValue': v},
    };
  }
  return {
    'userEnteredValue': {'stringValue': strPython(v)},
  };
}

/// Resultado de `Google.ler`: toda aba do esquema presente (vazia se não veio
/// da planilha) e cada linha completada com `""` e cortada na largura.
Map<String, List<Linha>> normalizarLeitura(
  Map<String, List<List<Object?>>> lidas,
) {
  return {
    for (final aba in esquemaAbas)
      aba.nome: [
        for (final linha in lidas[aba.nome] ?? const <List<Object?>>[])
          [
            for (var i = 0; i < aba.colunas.length; i++)
              i < linha.length ? linha[i] : '',
          ],
      ],
  };
}
