import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';
import '../apoio/cliente_falso.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  group('funções puras', () {
    test('idArtigo: só links do Google Notícias', () {
      expect(
        idArtigo('https://news.google.com/rss/articles/CBMi_a-b?oc=5'),
        'CBMi_a-b',
      );
      expect(idArtigo('https://news.google.com/articles/X#y'), 'X');
      expect(idArtigo('https://exemplo.com/articles/X'), isNull);
      expect(idArtigo('https://news.google.com/home'), isNull);
    });

    test('assinaturaArtigo exige sg e ts', () {
      const completa = '<c-wiz data-n-a-sg="S1" data-n-a-ts="17"></c-wiz>';
      expect(assinaturaArtigo(completa), (sg: 'S1', ts: '17'));
      expect(assinaturaArtigo('<c data-n-a-sg="S1">'), isNull);
      expect(assinaturaArtigo('<c data-n-a-ts="17">'), isNull);
    });

    test('corpoDecodificacao escapa como o json.dumps (ensure_ascii)', () {
      final corpo = corpoDecodificacao('G', '1', 'a\\b é\u{1F600}\u007f');
      const b = r'\'; // uma barra invertida
      expect(
        corpo,
        contains('$b"a$b${b}b ${b}u00e9${b}ud83d${b}ude00${b}u007f$b"'),
      );
      expect(corpo, startsWith('[[["Fbv4je", "[\\"garturlreq\\",'));
      expect(corpo, endsWith(']"]]]'));
      expect(jsonDecode(corpo), isA<List<Object?>>());
    });

    test('urlDaRespostaBatch: formato do Google e respostas fora dele', () {
      const ok =
          ')]}\'\n\n[["wrb.fr","Fbv4je","[\\"garturlres\\",\\"https://s.com/m\\",1]"],'
          '["di",1],["af.httprm",1]]\n';
      expect(urlDaRespostaBatch(ok), 'https://s.com/m');
      expect(
        urlDaRespostaBatch(ok.replaceAll('https://s.com', 'ftp://s.com')),
        isNull,
      );
      expect(() => urlDaRespostaBatch(')]}\''), throwsFormatException);
      expect(() => urlDaRespostaBatch('x\n\n{}'), throwsFormatException);
      expect(() => urlDaRespostaBatch('x\n\nnão json'), throwsFormatException);
      expect(
        () => urlDaRespostaBatch('x\n\n[["wrb.fr"]]'),
        throwsFormatException,
      );
    });
  });

  group('decodificar_link do Python', () {
    for (final c in carregarCasos(
      'noticias_rede',
    ).where((c) => c.funcao == 'decodificar_link')) {
      test(c.nome, () async {
        ambiente = Ambiente.fixo();
        final e = _mapa(c.entrada);
        final saida = _mapa(c.saida);
        final falso = ClienteFalso.fila([
          for (final r in _lista(e['respostas']))
            RespostaFalsa(
              _mapa(r)['status']! as int,
              texto: _mapa(r)['texto']! as String,
              motivo: switch (_mapa(r)['status']! as int) {
                429 => 'Too Many Requests',
                403 => 'Forbidden',
                500 => 'Internal Server Error',
                _ => null,
              },
            ),
        ]);
        final servico = ServicoNoticias(
          cliente: falso,
          armazenamento: ArmazenamentoMemoria(),
          executar: executarDireto,
        );

        Object? resultado;
        Object? erro;
        try {
          resultado = await servico.decodificarLink(e['link']! as String);
        } catch (ex) {
          erro = ex;
        }

        final esperados = _lista(saida['pedidos']);
        expect(falso.pedidos, hasLength(esperados.length));
        for (final (i, bruto) in esperados.indexed) {
          final esperado = _mapa(bruto);
          final pedido = falso.pedidos[i];
          expect(pedido.metodo, esperado['metodo']);
          // O requests percentual-codifica o que o Uri já codifica.
          expect(
            pedido.url.toString(),
            Uri.parse(esperado['url']! as String).toString(),
          );
          for (final h in _mapa(esperado['cabecalhos']).entries) {
            expect(
              pedido.cabecalhos[h.key.toLowerCase()],
              h.value,
              reason: h.key,
            );
          }
          final dados = esperado['dados'];
          if (dados == null) {
            expect(pedido.corpo, isEmpty);
          } else {
            // Mesmo `f.req`, caractere por caractere.
            expect(pedido.formulario, dados);
          }
        }

        if (saida.containsKey('erro')) {
          expect(erro, isNotNull, reason: 'devia lançar ${saida['erro']}');
          if (saida['erro'] == 'ErroHttp') {
            expect(erro, isA<ErroHttp>());
            expect(erro.toString(), saida['mensagem']);
          } else {
            expect(erro, isA<FormatException>());
          }
        } else {
          expect(erro, isNull);
          expect(resultado, saida['resultado']);
        }
      });
    }
  });
}
