import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';

List<Map<String, Object?>> _json(List<Noticia> l) => [
  for (final n in l) n.toJson(),
];

void main() {
  final todos = carregarCasos('noticias_rede');
  Iterable<Caso> casos(String funcao) => todos.where((c) => c.funcao == funcao);

  List<int> bytes(Object? e) =>
      utf8.encode((e! as Map<String, Object?>)['xml']! as String);
  String texto(Object? e, String chave) =>
      (e! as Map<String, Object?>)[chave]! as String;
  double agora(Object? e) =>
      ((e! as Map<String, Object?>)['agora']! as num).toDouble();

  for (final c in casos('ler_rss')) {
    test('ler_rss: ${c.nome}', () {
      final r = lerRss(
        bytes(c.entrada),
        texto(c.entrada, 'ticker'),
        nome: texto(c.entrada, 'nome'),
        agora: agora(c.entrada),
      );
      conferir(_json(r), c.saida);
    });
  }

  for (final c in casos('ler_rss_regex')) {
    final malformado = c.nome.endsWith('(malformado)');
    test('ler_rss pelas regex: ${c.nome}', () {
      final r = lerRssRegex(
        bytes(c.entrada),
        texto(c.entrada, 'ticker'),
        nome: texto(c.entrada, 'nome'),
        agora: agora(c.entrada),
      );
      conferir(_json(r), c.saida);
    });
    // Documento bem formado: o XML dá o mesmo que as regex; malformado:
    // `lerRss` cai nas regex.
    test(
      malformado
          ? 'ler_rss cai nas regex: ${c.nome}'
          : 'ler_rss (XML) dá o mesmo: ${c.nome}',
      () {
        final r = lerRss(
          bytes(c.entrada),
          texto(c.entrada, 'ticker'),
          nome: texto(c.entrada, 'nome'),
          agora: agora(c.entrada),
        );
        conferir(_json(r), c.saida);
      },
    );
  }

  for (final c in casos('data_rfc2822')) {
    test('data: ${c.nome}', () {
      conferir(lerDataRfc2822(c.entrada! as String), c.saida);
    });
  }

  for (final c in casos('url_busca')) {
    test('url: ${c.nome}', () {
      final e = c.entrada! as Map<String, Object?>;
      expect(
        urlBusca(e['ticker']! as String, nome: e['nome']! as String).toString(),
        c.saida,
      );
    });
  }

  for (final c in casos('quote')) {
    test('quote: ${c.nome}', () {
      final e = c.entrada! as Map<String, Object?>;
      expect(
        quotePython(e['texto']! as String, seguro: e['seguro']! as String),
        c.saida,
      );
    });
  }

  group('datas sem fuso', () {
    test('data sem fuso usa a hora local do aparelho', () {
      expect(
        lerDataRfc2822('Sat, 31 Oct 2026 14:00:00'),
        DateTime(2026, 10, 31, 14).millisecondsSinceEpoch / 1000,
      );
    });

    test('-0000 e fuso desconhecido também são locais', () {
      final local = DateTime(2026, 10, 31, 14).millisecondsSinceEpoch / 1000;
      expect(lerDataRfc2822('Sat, 31 Oct 2026 14:00:00 -0000'), local);
      expect(lerDataRfc2822('Sat, 31 Oct 2026 14:00:00 BRT'), local);
      expect(
        lerDataRfc2822('Sat, 31 Oct 2026 14:00:00 +0000'),
        DateTime.utc(2026, 10, 31, 14).millisecondsSinceEpoch / 1000,
      );
    });
  });

  group('rss', () {
    test('XML com namespace padrão não tem item (como o ElementTree)', () {
      const xml =
          '<rss xmlns="http://exemplo.com/ns"><channel><item>'
          '<title>Petrobras bate recorde de produção no pré-sal em outubro'
          '</title><link>https://x.com/a</link></item></channel></rss>';
      expect(lerRss(utf8.encode(xml), 'PETR4', agora: 1), isEmpty);
    });

    test('quebra de linha CRLF dentro do título vira LF', () {
      const xml =
          '<rss><item><title>Petrobras bate recorde\r\n de produção no pré-sal'
          '</title><link>https://x.com/a</link></item></rss>';
      expect(
        lerRss(utf8.encode(xml), 'PETR4', agora: 1).single.titulo,
        'Petrobras bate recorde\n de produção no pré-sal',
      );
    });

    test('bytes UTF-8 inválidos não lançam', () {
      final xml = [
        ...utf8.encode('<rss><item><title>Petrobras bate recorde de produção '),
        0xff,
        ...utf8.encode('</title><link>https://x.com/a</link></item></rss>'),
      ];
      expect(lerRss(xml, 'PETR4', agora: 1), hasLength(1));
    });
  });
}
