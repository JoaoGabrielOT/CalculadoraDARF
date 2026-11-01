import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';

void main() {
  final todos = carregarCasos('noticias_rede');
  Iterable<Caso> casos(String funcao) => todos.where((c) => c.funcao == funcao);

  test('tabela HTML5 igual à do Python', () {
    final caso = casos('tabela_html5').single;
    expect(entidadesHtml5.length, 2231);
    conferir(entidadesHtml5, caso.saida);
  });

  for (final caso in casos('unescape')) {
    test('unescape: ${caso.nome}', () {
      expect(unescapeHtml(caso.entrada! as String), caso.saida);
    });
  }

  for (final caso in casos('ler_previa')) {
    test('ler_previa: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      final r = lerPrevia(e['html']! as String, e['url']! as String);
      conferir({'img': r.img, 'resumo': r.resumo}, caso.saida);
    });
  }

  for (final caso in casos('meta')) {
    test('meta: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      final nomes = (e['nomes']! as List<Object?>).cast<String>();
      expect(metaDe(e['html']! as String, nomes), caso.saida);
    });
  }

  group('juntarUrl', () {
    test('resolve como o urljoin', () {
      expect(
        juntarUrl('https://a.com/x/y.html', '../z.png'),
        'https://a.com/z.png',
      );
    });

    test('referência inválida: http fica, o resto vira vazio', () {
      expect(juntarUrl('https://a.com/', 'http://[bad'), 'http://[bad');
      expect(juntarUrl('https://a.com/', 'https://[x'), 'https://[x');
      expect(juntarUrl('https://a.com/', '//[x'), '');
    });
  });
}
