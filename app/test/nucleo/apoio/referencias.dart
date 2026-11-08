import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Um caso gerado pelo Python 3.12 (ferramentas/gerar_referencias.py).
class Caso {
  const Caso(this.nome, this.funcao, this.entrada, this.saida);

  final String nome;
  final String funcao;
  final Object? entrada;
  final Object? saida;
}

/// Lê `test/referencias/<area>.json` (relativo ao diretório atual, `app/`).
List<Caso> carregarCasos(String area) {
  final doc = _lerDocumento(area);
  return [
    for (final bruto in doc['casos']! as List<Object?>)
      _caso(bruto! as Map<String, Object?>),
  ];
}

Caso _caso(Map<String, Object?> c) => Caso(
  c['nome']! as String,
  c['funcao']! as String,
  c['entrada'],
  c['saida'],
);

/// Versão do Python que gerou a área (campo `python` do cabeçalho).
String versaoPythonDasReferencias(String area) =>
    _lerDocumento(area)['python']! as String;

Map<String, Object?> _lerDocumento(String area) {
  final arquivo = File('test/referencias/$area.json');
  return jsonDecode(arquivo.readAsStringSync(encoding: utf8))
      as Map<String, Object?>;
}

/// Igualdade estrita entre [atual] e [esperado]; a falha cita o caminho.
///
/// `num` compara por valor e pelo sinal do zero (`int 0` = `0.0`, mas
/// `-0.0` != `0.0`). `Map` exige o mesmo conjunto de chaves. `List` compara na
/// ordem, exceto nos caminhos de [semOrdem] (comparação como multiconjunto).
void conferir(
  Object? atual,
  Object? esperado, {
  String caminho = r'$',
  Set<String> semOrdem = const {},
}) {
  if (atual is num && esperado is num) {
    final a = atual.toDouble();
    final e = esperado.toDouble();
    if (a != e || a.isNegative != e.isNegative) {
      fail('$caminho: obtido $atual, esperado $esperado');
    }
    return;
  }
  if (atual is Map && esperado is Map) {
    final ca = atual.keys.map((k) => '$k').toSet();
    final ce = esperado.keys.map((k) => '$k').toSet();
    if (ca.length != ce.length || !ca.containsAll(ce)) {
      fail(
        '$caminho: chaves diferentes; faltam ${ce.difference(ca)}, '
        'sobram ${ca.difference(ce)}',
      );
    }
    for (final k in ce) {
      conferir(
        atual[k],
        esperado[k],
        caminho: '$caminho.$k',
        semOrdem: semOrdem,
      );
    }
    return;
  }
  if (atual is List && esperado is List) {
    if (atual.length != esperado.length) {
      fail('$caminho: tamanho ${atual.length}, esperado ${esperado.length}');
    }
    if (semOrdem.contains(caminho)) {
      final restantes = [...esperado];
      for (var i = 0; i < atual.length; i++) {
        final j = restantes.indexWhere((e) => _igual(atual[i], e));
        if (j < 0) fail('$caminho[$i]: ${atual[i]} sem par em $esperado');
        restantes.removeAt(j);
      }
      return;
    }
    for (var i = 0; i < atual.length; i++) {
      conferir(
        atual[i],
        esperado[i],
        caminho: '$caminho[$i]',
        semOrdem: semOrdem,
      );
    }
    return;
  }
  if (atual != esperado) {
    fail('$caminho: obtido $atual, esperado $esperado');
  }
}

bool _igual(Object? a, Object? e) {
  try {
    conferir(a, e);
    return true;
  } on TestFailure {
    return false;
  }
}

/// Linhas gravadas sem a 14ª coluna do Resumo (Detalhes, só da 2.1), para
/// comparar com o Python, que grava 13. Exige a coluna vazia: as referências
/// não têm meses com o marcador de custo médio.
Map<String, List<List<Object?>>> semDetalhesDoResumo(
  Map<String, List<List<Object?>>> linhas,
) => {
  for (final e in linhas.entries)
    e.key: e.key != 'Resumo'
        ? e.value
        : [
            for (final l in e.value)
              () {
                expect(l, hasLength(14));
                expect(l[13], '');
                return l.sublist(0, 13);
              }(),
          ],
};
