// A 2.1 tem uma 14ª coluna no Resumo (Detalhes, oculta) que o Python não
// tem. Para comparar com os pedidos gravados pelo Python, estas funções tiram
// dos pedidos e da leitura do Dart só o que é dessa coluna.

/// Índice da coluna Detalhes do Resumo.
const _detalhes = 13;

/// `sheetId` da aba Resumo em qualquer `properties` de [json], ou nulo.
int? idDoResumo(Object? json) {
  if (json is List) {
    for (final x in json) {
      final id = idDoResumo(x);
      if (id != null) return id;
    }
  } else if (json is Map) {
    if (json['title'] == 'Resumo' && json['sheetId'] is int) {
      return json['sheetId']! as int;
    }
    for (final x in json.values) {
      final id = idDoResumo(x);
      if (id != null) return id;
    }
  }
  return null;
}

/// O pedido [v] como o Python o montaria, com o Resumo de 13 colunas
/// ([resumo]: o `sheetId` da aba): sem os pedidos só da coluna Detalhes, com
/// 13 no lugar de 14 em `columnCount` e `endColumnIndex`, uma coluna a menos
/// no `appendDimension` e as linhas gravadas cortadas em 13 células.
Object? layoutPython(Object? v, int? resumo) {
  bool doResumo(Object? r) => r is Map && r['sheetId'] == resumo;
  if (v is List) {
    return [
      for (final x in v)
        if (!_soDetalhes(x, resumo)) layoutPython(x, resumo),
    ];
  }
  if (v is! Map) return v;
  final m = <String, Object?>{
    for (final e in v.entries) '${e.key}': layoutPython(e.value, resumo),
  };
  final grade = m['gridProperties'];
  if (m['title'] == 'Resumo' && grade is Map && grade['columnCount'] == 14) {
    m['gridProperties'] = {...grade, 'columnCount': 13};
  }
  if (doResumo(m) && m['endColumnIndex'] == _detalhes + 1) {
    m['endColumnIndex'] = _detalhes;
  }
  final mais = m['appendDimension'];
  if (mais is Map && doResumo(mais) && mais['dimension'] == 'COLUMNS') {
    m['appendDimension'] = {...mais, 'length': (mais['length']! as int) - 1};
  }
  final celulas = m['updateCells'];
  if (celulas is Map && doResumo(celulas['range'])) {
    m['updateCells'] = {
      ...celulas,
      'rows': [
        for (final r in celulas['rows']! as List<Object?>)
          {
            ...r! as Map,
            'values': [...((r as Map)['values']! as List<Object?>).take(13)],
          },
      ],
    };
  }
  return m;
}

/// Pedido que só existe por causa da coluna Detalhes: o `appendDimension` de
/// uma coluna no Resumo ou um pedido cuja faixa começa nela.
bool _soDetalhes(Object? pedido, int? resumo) {
  if (pedido is! Map || pedido.length != 1) return false;
  final corpo = pedido.values.single;
  if (corpo is! Map) return false;
  if (pedido.keys.single == 'appendDimension') {
    return corpo['sheetId'] == resumo &&
        corpo['dimension'] == 'COLUMNS' &&
        corpo['length'] == 1;
  }
  final faixa = corpo['range'];
  if (faixa is! Map || faixa['sheetId'] != resumo) return false;
  return (faixa['dimension'] == 'COLUMNS' &&
          faixa['startIndex'] == _detalhes) ||
      faixa['startColumnIndex'] == _detalhes;
}

/// A leitura do Dart como a do Python, que corta o Resumo em 13 colunas.
Object? leituraPython(Object? lido) {
  if (lido is! Map || lido['Resumo'] is! List) return lido;
  return {
    ...lido,
    'Resumo': [
      for (final l in lido['Resumo']! as List<Object?>)
        (l! as List<Object?>).take(13).toList(),
    ],
  };
}
