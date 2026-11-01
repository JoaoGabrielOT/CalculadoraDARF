import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _pubAntiga = 'Mon, 20 Oct 2025 10:00:00 GMT';
const _pubNova = 'Mon, 20 Oct 2025 22:00:00 GMT';

String _item(String titulo, {String pub = _pubAntiga, String? link}) =>
    '<item><title>$titulo - Valor</title>'
    '<link>${link ?? 'https://news.google.com/rss/articles/X${titulo.hashCode}'}'
    '</link><pubDate>$pub</pubDate>'
    '<source url="https://valor.globo.com">Valor</source></item>';

String _rss(List<String> itens) =>
    '<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>'
    '<title>x</title>${itens.join()}</channel></rss>';

const _tituloA = 'Petrobras anuncia dividendos extraordinários de bilhões';
const _tituloB = 'Vale eleva produção de minério no terceiro trimestre';

Noticia _noticia(String id, {String? link}) => Noticia(
  id: id,
  titulo: 'Título da matéria $id sobre o mercado',
  link: link ?? 'https://site.com/$id',
  fonte: 'Valor',
  fonteUrl: '',
  data: 1760000000,
  tickers: ['PETR4'],
  temas: [],
);

String _html(String id) =>
    '<html><head><meta property="og:image" content="/img/$id.jpg">'
    '<meta name="description" content="Resumo $id"></head><body></body></html>';

ServicoNoticias _servico(ClienteFalso falso, Armazenamento a) =>
    ServicoNoticias(cliente: falso, armazenamento: a, executar: executarDireto);

Future<Object?> _capturar(Future<Object?> Function() f) async {
  try {
    await f();
  } catch (e) {
    return e;
  }
  return null;
}

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  group('buscarTicker', () {
    test(
      'URL do Python, UA de notícias; 429 → LimiteConsultas; 500 → ErroHttp',
      () async {
        final falso = ClienteFalso.fila([
          RespostaFalsa(200, texto: _rss([_item(_tituloA)])),
          RespostaFalsa(429, motivo: 'Too Many Requests'),
          RespostaFalsa(500, motivo: 'Internal Server Error'),
        ]);
        final s = _servico(falso, ArmazenamentoMemoria());

        final itens = await s.buscarTicker('PETR4');
        expect(itens, hasLength(1));
        expect(itens.single.tickers, ['PETR4']);
        expect(falso.pedidos.single.url, urlBusca('PETR4'));
        expect(
          falso.pedidos.single.cabecalhos['user-agent'],
          'Mozilla/5.0 (CalculadoraDARF)',
        );

        final limite = await _capturar(() => s.buscarTicker('VALE3'));
        expect(limite, isA<LimiteConsultas>());
        expect(limite.toString(), 'Too Many Requests');
        expect(falso.pedidos, hasLength(2), reason: '429 não repete');

        final erro = await _capturar(() => s.buscarTicker('VALE3'));
        expect(erro, isA<ErroHttp>());
        expect(
          erro.toString(),
          '500 Server Error: Internal Server Error for url: '
          '${urlBusca('VALE3')}',
        );
      },
    );
  });

  group('atualizar', () {
    test(
      'um ativo com erro não impede os outros; erro com até 200 caracteres',
      () async {
        final longo = '${'x' * 199}😀😀';
        final falso = ClienteFalso((p) {
          final q = p.url.queryParameters['q']!;
          if (q.contains('VALE3')) {
            return RespostaFalsa(200, erro: ErroValidacao(longo));
          }
          return RespostaFalsa(
            200,
            texto: _rss([_item(q.contains('PETR4') ? _tituloA : _tituloB)]),
          );
        });
        final arm = ArmazenamentoMemoria();
        final (itens, _) = await _servico(
          falso,
          arm,
        ).atualizar([('PETR4', ''), ('VALE3', ''), ('ITUB4', '')]);
        expect(itens.expand((i) => i.tickers).toSet(), {'PETR4', 'ITUB4'});
        final erros = lerEstado(arm).erros;
        expect(erros.keys, ['VALE3']);
        expect(erros['VALE3']!.runes.length, 200);
        expect(erros['VALE3'], '${'x' * 199}😀');
      },
    );

    test(
      'listas na ordem do radar mesmo com respostas fora de ordem',
      () async {
        final falso = ClienteFalso((p) {
          final lenta = p.url.queryParameters['q']!.contains('PETR4');
          return RespostaFalsa(
            200,
            texto: _rss([_item(_tituloA)]),
            atraso: Duration(milliseconds: lenta ? 80 : 0),
          );
        });
        final (itens, _) = await _servico(
          falso,
          ArmazenamentoMemoria(),
        ).atualizar([('PETR4', ''), ('VALE3', '')]);
        expect(itens.single.tickers, ['PETR4', 'VALE3']);
      },
    );

    test(
      'grava o estado como aplicarBusca e devolve as novas relevantes',
      () async {
        final arm = ArmazenamentoMemoria();
        final radar = [('PETR4', '')];
        var corpo = _rss([_item(_tituloB, pub: _pubAntiga)]);
        final falso = ClienteFalso((_) => RespostaFalsa(200, texto: corpo));
        final s = _servico(falso, arm);
        final agora1 = lerDataRfc2822(_pubNova)! + 3600;
        final (_, novas1) = await s.atualizar(radar, agora: agora1);
        expect(
          novas1,
          isEmpty,
          reason: 'estreia do ativo: só marca como visto',
        );

        corpo = _rss([
          _item(_tituloB, pub: _pubAntiga),
          _item(_tituloA, pub: _pubNova),
        ]);
        final agora2 = agora1 + 60;
        final (itens, novas) = await s.atualizar(radar, agora: agora2);
        expect(novas.map((n) => n.titulo), [startsWith('Petrobras anuncia')]);

        // Mesma conta, feita direto com o núcleo.
        final esperado = ArmazenamentoMemoria();
        final d1 = EstadoNoticias();
        aplicarBusca(
          d1,
          radar,
          [
            lerRss(
              utf8.encode(_rss([_item(_tituloB, pub: _pubAntiga)])),
              'PETR4',
              agora: 0,
            ),
          ],
          {},
          agora1,
        );
        final novasEsperadas = aplicarBusca(
          d1,
          radar,
          [lerRss(utf8.encode(corpo), 'PETR4', agora: 0)],
          {},
          agora2,
        );
        gravarEstado(esperado, d1);
        expect(arm.ler('noticias.json'), esperado.ler('noticias.json'));
        expect(novas.map((n) => n.id), novasEsperadas.map((n) => n.id));
        expect(itens.map((n) => n.id), d1.itens.map((n) => n.id));
      },
    );

    test(
      'com detalhes, busca as prévias; falha delas não derruba a busca',
      () async {
        final arm = ArmazenamentoMemoria();
        final falso = ClienteFalso((p) {
          if (p.url.host == 'news.google.com' && p.url.path == '/rss/search') {
            return RespostaFalsa(
              200,
              texto: _rss([_item(_tituloA, link: 'https://site.com/a')]),
            );
          }
          return RespostaFalsa(
            200,
            texto: _html('a'),
            cabecalhos: {'content-type': 'text/html; charset=utf-8'},
          );
        });
        final s = _servico(falso, arm);
        final (itens, _) = await s.atualizar([('PETR4', '')], detalhes: true);
        expect(lerDetalhes(arm)[itens.single.id]!.resumo, 'Resumo a');
      },
    );
  });

  group('baixarPagina', () {
    ServicoNoticias servico(RespostaFalsa r) =>
        _servico(ClienteFalso.fila([r]), ArmazenamentoMemoria());
    final html = utf8.encode('<html><head><title>t</title>');

    test('para no </head>, devolve a URL final e ignora o resto', () async {
      final (texto, url) = await servico(
        RespostaFalsa(
          200,
          blocos: [
            html,
            utf8.encode('<meta name="description" content="x"></head><body>'),
            utf8.encode('NUNCA LIDO'),
          ],
          cabecalhos: {'content-type': 'text/html'},
          urlFinal: Uri.parse('https://final.com/materia'),
        ),
      ).baixarPagina('https://orig.com/a');
      expect(texto, contains('</head>'));
      expect(texto, isNot(contains('NUNCA LIDO')));
      expect(url, 'https://final.com/materia');
    });

    test('para também quando o </head> cai na emenda de dois blocos', () async {
      final (texto, _) = await servico(
        RespostaFalsa(
          200,
          blocos: [
            utf8.encode('<head></he'),
            utf8.encode('ad>'),
            utf8.encode('DEPOIS'),
          ],
        ),
      ).baixarPagina('https://orig.com/a');
      expect(texto, '<head></head>');
    });

    test('respeita o limite de bytes', () async {
      final bloco = utf8.encode('a' * 1000);
      final (texto, _) = await servico(
        RespostaFalsa(200, blocos: [bloco, bloco, bloco, bloco, bloco]),
      ).baixarPagina('https://orig.com/a', limite: 2500);
      expect(texto.length, 3000);
    });

    test('ignora o que não é HTML; sem Content-Type conta como HTML', () async {
      final (pdf, urlPdf) = await servico(
        RespostaFalsa(
          200,
          bytes: [1, 2, 3],
          cabecalhos: {'content-type': 'application/pdf'},
        ),
      ).baixarPagina('https://orig.com/a.pdf');
      expect(pdf, '');
      expect(urlPdf, 'https://orig.com/a.pdf');

      final (semTipo, _) = await servico(RespostaFalsa(200, bytes: html))
          .baixarPagina('https://orig.com/a');
      expect(semTipo, contains('<title>t</title>'));
    });

    test('status de erro é ErroHttp', () async {
      final erro = await _capturar(
        () =>
            servico(RespostaFalsa(404, motivo: 'Not Found'))
                .baixarPagina('https://orig.com/a'),
      );
      expect(erro, isA<ErroHttp>());
      expect(
        erro.toString(),
        '404 Client Error: Not Found for url: https://orig.com/a',
      );
    });

    test('charset do cabeçalho, e UTF-8 quando não há', () async {
      final (latin, _) = await servico(
        RespostaFalsa(
          200,
          bytes: latin1.encode('<head>ação</head>'),
          cabecalhos: {'content-type': 'text/html; charset=ISO-8859-1'},
        ),
      ).baixarPagina('https://orig.com/a');
      expect(latin, '<head>ação</head>');

      final (padrao, _) = await servico(
        RespostaFalsa(
          200,
          bytes: utf8.encode('<head>ação</head>'),
          cabecalhos: {'content-type': 'text/html'},
        ),
      ).baixarPagina('https://orig.com/a');
      expect(padrao, '<head>ação</head>');

      final (ruim, _) = await servico(
        RespostaFalsa(
          200,
          bytes: [...utf8.encode('<head>a'), 0xff, ...utf8.encode('</head>')],
        ),
      ).baixarPagina('https://orig.com/a');
      expect(ruim, '<head>a${String.fromCharCode(0xfffd)}</head>');
    });
  });

  group('detalhar', () {
    test('link não decodificado → erro "link"', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, texto: '<html>sem assinatura</html>'),
      ]);
      final d = await _servico(falso, ArmazenamentoMemoria()).detalhar(
        _noticia('a', link: 'https://news.google.com/rss/articles/CBMi?oc=5'),
      );
      expect(d.erro, 'link');
      expect(d.url, '');
      expect(d.hora, ambiente.agora());
    });

    test('exceção → erro com até 120 caracteres', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, erro: ErroConexao('${'y' * 119}😀😀')),
      ]);
      final d = await _servico(
        falso,
        ArmazenamentoMemoria(),
      ).detalhar(_noticia('a'));
      expect(d.erro, '${'y' * 119}😀');
      expect(d.url, 'https://site.com/a');
    });

    test('sucesso com img e resumo, decodificando o link do Google', () async {
      final falso = ClienteFalso((p) {
        if (p.url.path.startsWith('/rss/articles/')) {
          return RespostaFalsa(
            200,
            texto: '<c data-n-a-sg="S" data-n-a-ts="9">',
          );
        }
        if (p.url.path.endsWith('batchexecute')) {
          return RespostaFalsa(
            200,
            texto:
                ')]}\'\n\n[["wrb.fr","Fbv4je","[\\"garturlres\\",\\"https://site.com/m/x\\",1]"],'
                '["di",1],["af",1]]\n',
          );
        }
        return RespostaFalsa(
          200,
          texto: _html('x'),
          cabecalhos: {'content-type': 'text/html; charset=utf-8'},
          urlFinal: Uri.parse('https://site.com/m/final'),
        );
      });
      final d = await _servico(falso, ArmazenamentoMemoria()).detalhar(
        _noticia('a', link: 'https://news.google.com/rss/articles/CBMi?oc=5'),
      );
      expect(d.erro, isNull);
      expect(d.url, 'https://site.com/m/final');
      expect(d.img, 'https://site.com/img/x.jpg');
      expect(d.resumo, 'Resumo x');
      expect(d.hora, ambiente.agora());
    });
  });

  group('enriquecer', () {
    ClienteFalso paginas({Duration atraso = Duration.zero}) => ClienteFalso(
      (p) => RespostaFalsa(
        200,
        texto: _html(p.url.pathSegments.last),
        cabecalhos: {'content-type': 'text/html'},
        atraso: atraso,
      ),
    );

    test('só os 40 mais recentes sem detalhe ou com erro há mais de 6 h; grava só os ids atuais', () async {
      final agora = ambiente.agora();
      final itens = [for (var i = 0; i < 45; i++) _noticia('n$i')];
      final arm = ArmazenamentoMemoria();
      gravarDetalhes(arm, {
        'n0': DetalheNoticia(url: 'u', hora: agora - 100),
        'n1': DetalheNoticia(hora: agora - 7 * 3600, erro: 'velho'),
        'n2': DetalheNoticia(hora: agora - 3600, erro: 'recente'),
        'n44': DetalheNoticia(hora: agora - 100),
        'fora': DetalheNoticia(url: 'sumiu', hora: agora),
      });
      final falso = paginas();
      final s = _servico(falso, arm);
      expect(await s.enriquecer(itens), isTrue);

      final buscados = falso.pedidos
          .map((p) => p.url.pathSegments.last)
          .toSet();
      expect(buscados, {'n1', for (var i = 3; i < 40; i++) 'n$i'});
      final det = lerDetalhes(arm);
      expect(det.keys.toSet(), {for (var i = 0; i < 40; i++) 'n$i', 'n44'});
      expect(det.containsKey('fora'), isFalse);
      expect(det['n0']!.url, 'u', reason: 'o que já tinha detalhe fica');
      expect(det['n2']!.erro, 'recente');
      expect(
        det['n44']!.hora,
        agora - 100,
        reason: 'fora do limite, mas já tinha',
      );
      expect(det['n1']!.erro, isNull);
      expect(det['n1']!.resumo, 'Resumo n1');
      expect(det.containsKey('n40'), isFalse);
    });

    test('sem nada a fazer devolve false e não grava', () async {
      final agora = ambiente.agora();
      final arm = ArmazenamentoMemoria();
      gravarDetalhes(arm, {
        'n0': DetalheNoticia(hora: agora),
        'velho': DetalheNoticia(hora: agora),
      });
      final antes = arm.ler(arquivoDetalhes);
      final falso = paginas();
      expect(await _servico(falso, arm).enriquecer([_noticia('n0')]), isFalse);
      expect(falso.pedidos, isEmpty);
      expect(arm.ler(arquivoDetalhes), antes);
    });

    test('no máximo 4 detalhes ao mesmo tempo', () async {
      final falso = paginas(atraso: const Duration(milliseconds: 30));
      final itens = [for (var i = 0; i < 12; i++) _noticia('n$i')];
      await _servico(falso, ArmazenamentoMemoria()).enriquecer(itens);
      expect(falso.pedidos, hasLength(12));
      expect(falso.maxSimultaneos, 4);
    });
  });

  group('noticias_detalhes.json', () {
    test('chaves e formato do Python', () {
      final arm = ArmazenamentoMemoria();
      gravarDetalhes(arm, {
        'a': DetalheNoticia(
          url: 'https://x.com',
          img: 'i',
          resumo: 'ação',
          hora: 1.5,
        ),
        'b': DetalheNoticia(hora: 2, erro: 'link'),
      });
      expect(
        arm.ler(arquivoDetalhes),
        '{"a": {"url": "https://x.com", "img": "i", "resumo": "ação", '
        '"hora": 1.5}, "b": {"url": "", "img": "", "resumo": "", '
        '"hora": 2.0, "erro": "link"}}',
      );
      final volta = lerDetalhes(arm);
      expect(volta['a']!.resumo, 'ação');
      expect(volta['a']!.erro, isNull);
      expect(volta['b']!.erro, 'link');
      expect(volta['b']!.hora, 2.0);
    });

    test('arquivo ausente ou ilegível dá mapa vazio; manter filtra', () {
      final arm = ArmazenamentoMemoria();
      expect(lerDetalhes(arm), isEmpty);
      arm.gravar(arquivoDetalhes, '{quebrado');
      expect(lerDetalhes(arm), isEmpty);
      arm.gravar(arquivoDetalhes, '[1, 2]');
      expect(lerDetalhes(arm), isEmpty);
      gravarDetalhes(
        arm,
        {'a': DetalheNoticia(hora: 1), 'b': DetalheNoticia(hora: 2)},
        manter: {'b'},
      );
      expect(lerDetalhes(arm).keys, ['b']);
    });
  });
}
