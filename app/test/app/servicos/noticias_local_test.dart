import 'dart:typed_data';

import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/locais/noticias_local.dart';
import 'package:calculadoradarf/app/servicos/servicos_locais.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integracoes/apoio/cliente_falso.dart';
import '../apoio/conta_falsa.dart';
import '../apoio/yahoo_falso.dart';

late ArmazenamentoMemoria disco;
late Repositorio repo;
late ClienteFalso falso;
late CacheBinarioMemoria cache;
late NoticiasLocal noticias;
late List<EventoServico> eventos;

/// Resposta por pedido; o padrão é 404.
late RespostaFalsa Function(PedidoGravado) responder;

/// Pedidos do Google Notícias (a busca por ticker).
Iterable<PedidoGravado> get buscas =>
    falso.pedidos.where((p) => p.url.host == 'news.google.com');

String rss(String titulo, {String ticker = 'PETR4'}) =>
    '<rss><channel><item><title>$titulo</title>'
    '<link>https://exemplo.com/$ticker</link>'
    '<pubDate>Mon, 20 Oct 2025 22:00:00 GMT</pubDate>'
    '<source url="https://exemplo.com">Exemplo</source>'
    '</item></channel></rss>';

RespostaFalsa _padrao(PedidoGravado p) {
  if (p.url.host == 'news.google.com' && p.url.path == '/rss/search') {
    return RespostaFalsa(200, texto: rss('Petrobras divulga fato relevante'));
  }
  return RespostaFalsa(404, texto: 'nada', motivo: 'Not Found');
}

void radar(List<String> tickers) {
  final cfg = repo.lerConfig();
  for (final t in tickers) {
    adicionarRadar(cfg, t);
  }
  repo.gravarConfig(cfg, carimbar: false);
}

/// Estado de notícias em que [tickers] já foram buscados há [minutos].
void estadoRecente(List<String> tickers, {int minutos = 1}) {
  final d = EstadoNoticias(
    hora: ambiente.agora() - minutos * 60,
    conhecidos: tickers,
  );
  gravarEstado(disco, d);
}

Noticia materia(String id, {String fonteUrl = ''}) => Noticia(
  id: id,
  titulo: 'T $id',
  link: 'https://exemplo.com/$id',
  fonte: 'F',
  fonteUrl: fonteUrl,
  data: 1,
  tickers: ['PETR4'],
  temas: [],
);

NoticiasLocal montar(void Function(EventoServico) emitir) => NoticiasLocal(
  repo: repo,
  servico: ServicoNoticias(
    cliente: falso,
    armazenamento: disco,
    executar: executarDireto,
  ),
  logos: Logos(http: ClienteHttp(falso), cache: cache),
  cache: cache,
  navegador: ClienteHttp(falso),
  emitir: emitir,
);

void main() {
  setUp(() {
    ambiente = Ambiente.fixo();
    disco = ArmazenamentoMemoria();
    repo = Repositorio(disco);
    cache = CacheBinarioMemoria();
    responder = _padrao;
    falso = ClienteFalso((p) => responder(p));
    eventos = [];
    noticias = montar(eventos.add);
  });

  tearDown(() => ambiente = Ambiente.sistema());

  group('atualizarNoticias', () {
    test(
      'a visão traz o radar na ordem do usuário e os ids das novas',
      () async {
        radar(['PETR4', 'VALE3']);
        final cfg = repo.lerConfig();
        reordenarRadar(cfg, ['VALE3', 'PETR4']);
        repo.gravarConfig(cfg, carimbar: false);
        gravarEstado(
          disco,
          EstadoNoticias(
            itens: [materia('velha'), materia('nova')],
            vistos: {'velha': 100, 'nova': 300},
            lidasAte: 200,
            hora: ambiente.agora(),
            conhecidos: ['PETR4', 'VALE3'],
          ),
        );
        final v = await noticias.noticias();
        expect([for (final r in v.radar) r.$1], ['VALE3', 'PETR4']);
        expect(v.novas, {'nova'});
        expect(v.naoLidas, 1);
      },
    );

    test('atualizarNoticias sem radar não busca', () async {
      final v = await noticias.atualizarNoticias(forcar: true);
      expect(falso.pedidos, isEmpty);
      expect(v.itens, isEmpty);
      expect(v.radar, isEmpty);
    });

    test('sem forcar e sem precisaAtualizar não busca, salvo ativo do radar '
        'ainda desconhecido', () async {
      radar(['PETR4']);
      estadoRecente(['PETR4']);
      await noticias.atualizarNoticias();
      expect(falso.pedidos, isEmpty);

      radar(['VALE3']); // VALE3 nunca foi buscado
      await noticias.atualizarNoticias();
      expect(buscas, isNotEmpty);
    });

    test('forcar busca mesmo com o estado recente', () async {
      radar(['PETR4']);
      estadoRecente(['PETR4']);
      await noticias.atualizarNoticias(forcar: true);
      expect(buscas, isNotEmpty);
    });

    test('busca em andamento não dispara outra', () async {
      radar(['PETR4']);
      responder = (p) => p.url.host == 'news.google.com'
          ? RespostaFalsa(
              200,
              texto: rss('x'),
              atraso: const Duration(milliseconds: 50),
            )
          : _padrao(p);
      final primeira = noticias.atualizarNoticias(forcar: true);
      await Future<void>.delayed(Duration.zero);
      final segunda = await noticias.atualizarNoticias(forcar: true);
      expect(segunda.rodando, isTrue);
      final fim = await primeira;
      expect(fim.rodando, isFalse);
      expect(buscas, hasLength(1));
    });

    test('um ativo com erro aparece em erros e não derruba a busca', () async {
      radar(['PETR4']);
      responder = (_) => RespostaFalsa(500, texto: 'x', motivo: 'Erro');
      final v = await noticias.atualizarNoticias(forcar: true);
      expect(v.erros.keys, ['PETR4']);
      expect(v.itens, isEmpty);
    });

    test('novas relevantes geram EventoNoticias com os textos de '
        'textosNotificacao', () async {
      radar(['PETR4']);
      // PETR4 já é conhecido e nada foi visto: a matéria é nova
      gravarEstado(disco, EstadoNoticias(conhecidos: ['PETR4']));
      final v = await noticias.atualizarNoticias(forcar: true);
      final e = eventos.whereType<EventoNoticias>().single;
      expect(e.visao.itens.map((i) => i.id), v.itens.map((i) => i.id));
      expect(e.notificar, hasLength(1));
      expect(e.notificar.single, textosNotificacao([v.itens.single]).single);
      expect(e.notificar.single.$1, contains('PETR4'));
      expect(e.visao.rodando, isFalse);
    });

    test('primeira busca de um ativo não notifica', () async {
      radar(['PETR4']);
      await noticias.atualizarNoticias(forcar: true);
      expect(eventos.whereType<EventoNoticias>().single.notificar, isEmpty);
    });

    test('a busca pede as prévias (detalhes) das matérias', () async {
      radar(['PETR4']);
      await noticias.atualizarNoticias(forcar: true);
      expect(
        falso.pedidos.any(
          (p) => p.url.toString() == 'https://exemplo.com/PETR4',
        ),
        isTrue,
      );
      expect((await noticias.noticias()).detalhes, isNotEmpty);
    });

    test('tick usa o limite de 10 minutos de precisaAtualizar', () async {
      radar(['PETR4']);
      estadoRecente(['PETR4'], minutos: 11);
      await noticias.tick();
      expect(buscas, hasLength(1));
      await noticias.tick();
      expect(buscas, hasLength(1));
    });

    test('tick não lança quando a config está ilegível', () async {
      radar(['PETR4']);
      estadoRecente(['PETR4'], minutos: 11);
      disco.gravar('config.json', '{');
      await noticias.tick();
      expect(eventos.whereType<EventoNoticias>(), isEmpty);
    });

    test(
      'config ilegível: o erro chega a quem chamou e nada é buscado',
      () async {
        disco.gravar('config.json', '{');
        await expectLater(
          noticias.atualizarNoticias(forcar: true),
          throwsA(isA<ErroValidacao>()),
        );
        expect(falso.pedidos, isEmpty);
      },
    );

    test('falha no meio da busca libera a trava', () async {
      radar(['PETR4']);
      responder = (p) {
        if (p.url.host == 'news.google.com') {
          disco.gravar('noticias.json', '{');
        }
        return _padrao(p);
      };
      await noticias.atualizarNoticias(forcar: true);
      expect((await noticias.noticias()).rodando, isFalse);
    });
  });

  group('leitura e lidas', () {
    test('noticias devolve naoLidas e detalhes', () async {
      radar(['PETR4', 'VALE3']);
      gravarEstado(
        disco,
        EstadoNoticias(
          itens: [materia('a')],
          vistos: {'a': ambiente.agora()},
          hora: 5,
          lidasAte: 10,
          erros: {'VALE3': 'falhou'},
        ),
      );
      gravarDetalhes(disco, {'a': DetalheNoticia(hora: 1, resumo: 'r')});
      final v = await noticias.noticias();
      expect(v.naoLidas, 1);
      expect(v.detalhes['a']!.resumo, 'r');
      expect(v.hora, 5);
      expect(v.lidasAte, 10);
      expect(v.erros, {'VALE3': 'falhou'});
      expect(v.radar.map((r) => r.$1), ['PETR4', 'VALE3']);
      expect(v.rodando, isFalse);
    });

    test('marcarNoticiasLidas zera naoLidas', () async {
      radar(['PETR4']);
      gravarEstado(
        disco,
        EstadoNoticias(
          itens: [materia('a')],
          vistos: {'a': ambiente.agora() - 5},
          lidasAte: 1,
        ),
      );
      expect((await noticias.noticias()).naoLidas, 1);
      await noticias.marcarNoticiasLidas();
      expect((await noticias.noticias()).naoLidas, 0);
    });
  });

  group('imagens', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, //
    ]);
    final svg = Uint8List.fromList('<svg xmlns="x"></svg>'.codeUnits);

    test('logo: PNG primeiro, depois SVG (svg: true), depois null', () async {
      var servirPng = true;
      var servirSvg = true;
      responder = (p) {
        if (p.url.path.endsWith('.svg')) {
          return servirSvg
              ? RespostaFalsa(200, bytes: svg)
              : RespostaFalsa(404, texto: 'x', motivo: 'Not Found');
        }
        return servirPng
            ? RespostaFalsa(200, bytes: png)
            : RespostaFalsa(404, texto: 'x', motivo: 'Not Found');
      };
      final a = await noticias.logo('PETR4');
      expect(a!.svg, isFalse);
      expect(a.bytes, png);

      servirPng = false;
      cache = CacheBinarioMemoria();
      noticias = montar(eventos.add);
      final b = await noticias.logo('PETR4');
      expect(b!.svg, isTrue);
      expect(b.bytes, svg);

      servirSvg = false;
      cache = CacheBinarioMemoria();
      noticias = montar(eventos.add);
      expect(await noticias.logo('PETR4'), isNull);
    });

    test('favicon vem do cache de logos', () async {
      responder = (_) => RespostaFalsa(200, bytes: png);
      final item = materia('a', fonteUrl: 'https://exemplo.com');
      expect(await noticias.favicon(item), png);
    });

    test('imagemNoticia devolve os bytes do JPEG reduzido do cache', () async {
      const url = 'https://exemplo.com/a.jpg';
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 9, 9]);
      await cache.gravar(nomeImagemNoticia(url), jpeg);
      expect(await noticias.imagemNoticia(url), jpeg);
      expect(falso.pedidos, isEmpty);
    });

    test('imagemNoticia sem imagem disponível devolve null', () async {
      expect(await noticias.imagemNoticia('https://exemplo.com/b.jpg'), isNull);
    });
  });

  test('ServicosLocais repassa as notícias e os eventos', () async {
    radar(['PETR4']);
    final s = ServicosLocais(
      repo: repo,
      yahoo: yahooSemRede(),
      conta: ContaFalsa(email: 'ana@gmail.com'),
      abrirUrl: (_) async {},
      atrasoAgendamento: const Duration(hours: 1),
      noticias: montar,
    );
    final recebidos = <EventoServico>[];
    s.eventos.listen(recebidos.add);
    final v = await s.atualizarNoticias(forcar: true);
    await Future<void>.delayed(Duration.zero);
    expect(v.itens, hasLength(1));
    expect(recebidos.whereType<EventoNoticias>(), hasLength(1));
    expect((await s.noticias()).itens, hasLength(1));
    await s.encerrar();
  });
}
