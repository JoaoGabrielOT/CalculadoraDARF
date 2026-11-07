import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/componentes/logo_ativo.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/noticias/mural.dart';
import 'package:calculadoradarf/app/telas/noticias/tela_noticias.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 900);
const _medio = Size(900, 900);

/// Janelas altas: os cartões da lista preguiçosa ficam todos à vista.
const _pcAlto = Size(1366, 3000);
const _medioAlto = Size(900, 3000);
const _celular = Size(400, 850);
const _agora = 1761000000.123;

/// PNG 1x1 válido.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/'
  'iZk9HQAAAABJRU5ErkJggg==',
);

Noticia _n(
  String id, {
  String titulo = '',
  List<String> tickers = const ['PETR4'],
  List<String> temas = const [],
  double idade = 7200,
  String fonte = 'Fonte A',
}) => Noticia(
  id: id,
  titulo: titulo.isEmpty ? 'Título da notícia $id com texto razoável' : titulo,
  link: 'https://news.google.com/$id',
  fonte: fonte,
  fonteUrl: 'https://www.fonte-a.example.com/x',
  data: _agora - idade,
  tickers: tickers,
  temas: temas,
);

DetalheNoticia _d(String id, {bool img = true, String resumo = ''}) =>
    DetalheNoticia(
      url: 'https://materia.example.com/$id',
      img: img ? 'https://img.example.com/$id.jpg' : '',
      resumo: resumo,
      hora: _agora,
    );

const _radar = [('PETR4', 'Petrobras PN'), ('WEGE3', 'WEG ON')];

VisaoNoticias _visao({
  List<Noticia>? itens,
  Map<String, DetalheNoticia> detalhes = const {},
  Set<String> novas = const {},
  double hora = 0,
  Map<String, String> erros = const {},
  List<(String, String)> radar = _radar,
  int naoLidas = 0,
}) => VisaoNoticias(
  itens: itens ?? const [],
  detalhes: detalhes,
  naoLidas: naoLidas,
  hora: hora,
  lidasAte: 0,
  erros: erros,
  rodando: false,
  radar: radar,
  novas: novas,
);

/// Dez matérias: a primeira é o destaque (foto e tema).
List<Noticia> _mural() => [
  _n('a1', temas: ['Proventos'], titulo: 'Destaque do mural com foto grande'),
  _n(
    'a2',
    titulo:
        'Segunda matéria com foto e título um pouco mais longo '
        'para ocupar mais linhas no cartão do mural',
  ),
  _n('a3', tickers: ['WEGE3'], temas: ['Resultado']),
  _n('a4', tickers: ['WEGE3']),
  _n('a5'),
  _n('a6', tickers: ['WEGE3'], titulo: 'Curto sem foto nenhuma aqui hoje ok'),
  _n(
    'a7',
    titulo:
        'Sétima matéria com um título bem longo '
        'que precisa de várias linhas para ser exibido por inteiro no cartão '
        'e assim deixar a coluna mais alta do que as outras duas',
  ),
  _n('a8', tickers: ['WEGE3']),
];

Map<String, DetalheNoticia> _detalhesMural() => {
  for (final i in ['a1', 'a2', 'a3', 'a5', 'a7'])
    i: _d(i, resumo: 'Resumo da matéria $i'),
  for (final i in ['a4', 'a6', 'a8']) i: _d(i, img: false),
};

class _Cena {
  _Cena(this.servicos, this.plataforma);

  final ServicosFalsos servicos;
  final PlataformaFalsa plataforma;
}

Future<_Cena> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  bool naAba = true,
}) async {
  final cena = _Cena(servicos ?? ServicosFalsos(), PlataformaFalsa());
  await montarApp(
    t,
    servicos: cena.servicos,
    plataforma: cena.plataforma,
    tamanho: tamanho,
    tela: const TelaNoticias(),
  );
  await t.pumpAndSettle();
  if (naAba) {
    _estado(t).irPara(Aba.noticias);
    await t.pumpAndSettle();
  }
  return cena;
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaNoticias)), listen: false);

Finder _cartao(String id) => find.byKey(Key('cartao-noticia-$id'));

Finder _status() => find.byKey(const Key('status-noticias'));

String _textoStatus(WidgetTester t) => t.widget<Text>(_status()).data!;

ServicosFalsos _servicos({
  List<Noticia>? itens,
  Map<String, DetalheNoticia>? detalhes,
  Set<String> novas = const {},
  double hora = 0,
  Map<String, String> erros = const {},
  List<(String, String)> radar = _radar,
}) {
  final s = ServicosFalsos();
  s.visaoNoticias = _visao(
    itens: itens ?? _mural(),
    detalhes: detalhes ?? _detalhesMural(),
    novas: novas,
    hora: hora,
    erros: erros,
    radar: radar,
  );
  s.imagemNoticiaFn = (_) async => _png;
  return s;
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: '2026-10-28', agora: _agora));

  group('mural (puro)', () {
    test('cortar quebra na palavra e põe reticências', () {
      expect(cortar('  curto  ', 20), 'curto');
      expect(cortar('uma frase bem comprida, aqui', 12), 'uma frase…');
      expect(cortar('semespacosnenhum', 5), 'semes…');
      expect(cortar(null, 5), '');
    });

    test('linhas estima as linhas do texto', () {
      expect(linhas('', 300, 7), 0);
      expect(linhas(null, 300, 7), 0);
      expect(linhas('abc', 300, 7), 1);
      // 300 / 7 = 42 caracteres por linha
      expect(linhas('x' * 43, 300, 7), 2);
      // mínimo de 10 por linha
      expect(linhas('x' * 25, 20, 7), 3);
    });

    test('estiloNoticia: sem imagem é texto; com tema ou nas duas primeiras '
        'é grande; o resto é médio', () {
      final com = _d('x');
      final sem = _d('x', img: false);
      expect(estiloNoticia(_n('x'), null, 0), EstiloNoticia.texto);
      expect(estiloNoticia(_n('x'), sem, 0), EstiloNoticia.texto);
      expect(estiloNoticia(_n('x'), com, 1), EstiloNoticia.grande);
      expect(estiloNoticia(_n('x'), com, 2), EstiloNoticia.medio);
      expect(
        estiloNoticia(_n('x', temas: ['Resultado']), com, 5),
        EstiloNoticia.grande,
      );
    });

    test('distribuirMural manda cada cartão para a coluna mais baixa', () {
      final itens = [
        for (final i in ['a', 'b', 'c', 'd', 'e']) _n(i),
      ];
      const alturas = {'a': 100.0, 'b': 50.0, 'c': 50.0, 'd': 80.0, 'e': 10.0};
      final cols = distribuirMural(itens, 2, (n) => alturas[n.id]!);
      expect(
        [for (final c in cols) c.map((n) => n.id).toList()],
        [
          ['a', 'd'],
          ['b', 'c', 'e'],
        ],
      );
      expect(distribuirMural(itens, 1, (_) => 1), hasLength(1));
      expect(distribuirMural(const [], 3, (_) => 1), everyElement(isEmpty));
    });

    test('colunasMural: uma por 340 px, de 1 a 4', () {
      expect(colunasMural(300), 1);
      expect(colunasMural(660), 1);
      expect(colunasMural(700), 2);
      expect(colunasMural(1250), 3);
      expect(colunasMural(5000), 4);
    });
  });

  testWidgets('expandido: mural com colunas pela largura e cartões de '
      'tamanhos variados', (t) async {
    await _montar(t, servicos: _servicos(), tamanho: _pcAlto);
    final destaque = t.getRect(_cartao('a1'));
    final restantes = [
      for (final i in ['a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8'])
        t.getRect(_cartao(i)),
    ];
    // o destaque ocupa a largura toda; o resto fica em três colunas
    expect(destaque.width, greaterThan(1100));
    final xs = {for (final r in restantes) r.left.round()};
    expect(xs, hasLength(3));
    expect(restantes.first.width, lessThan(destaque.width / 2));
    // tamanhos variados
    expect(
      {for (final r in restantes) r.height.round()}.length,
      greaterThan(2),
    );
    // o destaque tem a imagem grande
    expect(find.byKey(const Key('imagem-noticia-a1')), findsOneWidget);
    final foto = t.getSize(find.byKey(const Key('imagem-noticia-a1')));
    expect(foto.width, closeTo(destaque.width * .48, 2));
    expect(foto.height, inInclusiveRange(260, 360));
    // a largura da janela muda as colunas
    t.view.physicalSize = _medioAlto;
    await t.pumpAndSettle();
    final xs2 = {
      for (final i in ['a2', 'a3', 'a4', 'a5'])
        if (_cartao(i).evaluate().isNotEmpty)
          t.getRect(_cartao(i)).left.round(),
    };
    expect(xs2, hasLength(2));
  });

  testWidgets('compacto: lista de cartões', (t) async {
    await _montar(t, servicos: _servicos(), tamanho: _celular);
    final a = t.getRect(_cartao('a1'));
    final b = t.getRect(_cartao('a2'));
    expect(a.left, b.left);
    expect(a.width, b.width);
    expect(b.top, greaterThan(a.bottom - 1));
    expect(a.width, greaterThan(300));
    // sem fotos no celular: só o logo do primeiro ativo
    expect(find.byKey(const Key('imagem-noticia-a1')), findsNothing);
    final logo = find.descendant(
      of: _cartao('a1'),
      matching: find.byType(LogoAtivo),
    );
    expect(logo, findsOneWidget);
    expect(t.widget<LogoAtivo>(logo).ticker, 'PETR4');
    expect(find.text('Notícias do radar'), findsOneWidget);
    expect(find.byTooltip('Atualizar'), findsOneWidget);
  });

  testWidgets('cartão: imagem quando chega, favicon da fonte, título, '
      'resumo, fonte · tempo relativo, selo Nova para não lidas', (t) async {
    final s = _servicos(
      itens: [
        _n('a1', temas: ['Proventos', 'Resultado'], tickers: ['PETR4']),
      ],
      detalhes: {'a1': _d('a1', resumo: 'O resumo da matéria original.')},
      novas: {'a1'},
    );
    final imagem = Completer<Uint8List?>();
    s.imagemNoticiaFn = (_) => imagem.future;
    s.faviconFn = (_) async => _png;
    await _montar(t, servicos: s);
    // a foto ainda não chegou: espaço reservado
    expect(find.byKey(const Key('foto-vazia-a1')), findsOneWidget);
    expect(find.byKey(const Key('imagem-noticia-a1')), findsNothing);
    imagem.complete(_png);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('imagem-noticia-a1')), findsOneWidget);
    expect(find.byKey(const Key('foto-vazia-a1')), findsNothing);
    expect(
      s.chamadas,
      contains('imagemNoticia(https://img.example.com/a1.jpg)'),
    );
    expect(find.byKey(const Key('favicon-a1')), findsOneWidget);
    expect(s.chamadas, contains('favicon(a1)'));
    expect(
      find.text('Título da notícia a1 com texto razoável'),
      findsOneWidget,
    );
    expect(find.text('O resumo da matéria original.'), findsOneWidget);
    expect(find.text('Fonte A'), findsOneWidget);
    expect(find.textContaining('há 2 h'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('PETR4'), findsOneWidget); // chip do ativo
    expect(find.text('Proventos'), findsOneWidget);
    expect(find.text('Resultado'), findsOneWidget);
  });

  testWidgets('cartão lido não tem selo; resumo igual ao título não repete; '
      'sem fonte usa o domínio do link', (t) async {
    final item = _n('a1', fonte: '', titulo: 'Título repetido no resumo aqui');
    final s = _servicos(
      itens: [item],
      detalhes: {'a1': _d('a1', resumo: 'Título repetido no resumo aqui')},
    );
    await _montar(t, servicos: s);
    expect(find.text('Nova'), findsNothing);
    expect(find.text('Título repetido no resumo aqui'), findsOneWidget);
    expect(find.text('materia.example.com'), findsOneWidget);
  });

  testWidgets('imagens só são pedidas para os cartões construídos', (t) async {
    final itens = [for (var i = 0; i < 60; i++) _n('m$i')];
    final s = _servicos(
      itens: itens,
      detalhes: {for (final n in itens) n.id: _d(n.id)},
    );
    await _montar(t, servicos: s, tamanho: _celular);
    final pedidas = s.chamadas
        .where((c) => c.startsWith('imagemNoticia'))
        .length;
    expect(pedidas, lessThan(60));
    // compacto não mostra foto, mas o favicon é pedido só dos construídos
    final favicons = s.chamadas.where((c) => c.startsWith('favicon')).length;
    expect(favicons, lessThan(60));
    expect(favicons, greaterThan(0));
    // no PC as fotos são pedidas só das colunas à vista
    await _montar(t, servicos: s);
    final pedidasPc = s.chamadas
        .where((c) => c.startsWith('imagemNoticia'))
        .length;
    expect(pedidasPc, lessThan(60));
    expect(pedidasPc, greaterThan(0));
  });

  testWidgets('filtros Todas/Relevantes e por ativo', (t) async {
    await _montar(t, servicos: _servicos());
    expect(_cartao('a2'), findsOneWidget);
    expect(_cartao('a3'), findsOneWidget);
    await t.tap(find.text('Relevantes'));
    await t.pumpAndSettle();
    expect(_cartao('a1'), findsOneWidget);
    expect(_cartao('a3'), findsOneWidget);
    expect(_cartao('a2'), findsNothing);
    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(_cartao('a2'), findsOneWidget);
    // por ativo
    await t.tap(find.byKey(const Key('menu-ativo-noticias')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PopupMenuItem<String>, 'WEGE3'));
    await t.pumpAndSettle();
    expect(_cartao('a3'), findsOneWidget);
    expect(_cartao('a4'), findsOneWidget);
    expect(_cartao('a1'), findsNothing);
    expect(_cartao('a2'), findsNothing);
    // os dois juntos
    await t.tap(find.text('Relevantes'));
    await t.pumpAndSettle();
    expect(_cartao('a3'), findsOneWidget);
    expect(_cartao('a4'), findsNothing);
  });

  testWidgets('só aparecem matérias de ativos que ainda estão no radar', (
    t,
  ) async {
    final s = _servicos(
      itens: [
        _n('a1'),
        _n('z1', tickers: ['VALE3']),
      ],
      detalhes: {},
    );
    await _montar(t, servicos: s);
    expect(_cartao('a1'), findsOneWidget);
    expect(_cartao('z1'), findsNothing);
  });

  testWidgets('tocar abre a matéria com abrirUrl (link da prévia no PC, '
      'link da notícia no celular)', (t) async {
    final s = _servicos(itens: [_n('a1')], detalhes: {'a1': _d('a1')});
    final cena = await _montar(t, servicos: s);
    await t.tap(_cartao('a1'));
    await t.pump();
    expect(
      cena.plataforma.urlsAbertas.single.toString(),
      'https://materia.example.com/a1',
    );
  });

  testWidgets('celular: o link é o da notícia', (t) async {
    final s = _servicos(itens: [_n('a1')], detalhes: {'a1': _d('a1')});
    final cena = await _montar(t, servicos: s, tamanho: _celular);
    await t.tap(_cartao('a1'));
    await t.pump();
    expect(
      cena.plataforma.urlsAbertas.single.toString(),
      'https://news.google.com/a1',
    );
  });

  testWidgets('link que não abre vira aviso', (t) async {
    final s = _servicos(itens: [_n('a1')], detalhes: {});
    final cena = await _montar(t, servicos: s);
    cena.plataforma.respostaAbrirUrl = false;
    await t.tap(_cartao('a1'));
    await t.pump();
    expect(_estado(t).avisos.single.texto, contains('navegador'));
  });

  testWidgets('rolar e arrastar a janela durante Atualizar', (t) async {
    final itens = [
      for (var i = 0; i < 30; i++) _n('m$i', tickers: ['PETR4']),
    ];
    final s = _servicos(
      itens: itens,
      detalhes: {for (final n in itens) n.id: _d(n.id, img: false)},
    );
    final espera = Completer<VisaoNoticias>();
    s.atualizarNoticiasFn = (_) => espera.future;
    await _montar(t, servicos: s);
    await t.tap(find.text('Atualizar'));
    await t.pump();
    expect(_textoStatus(t), 'Buscando notícias…');
    final rolagem = t.state<ScrollableState>(find.byType(Scrollable).first);
    expect(rolagem.position.pixels, 0);
    await t.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await t.pump();
    expect(rolagem.position.pixels, greaterThan(100));
    // arrasta a janela: de PC para celular e para outro tamanho, sem quebrar
    t.view.physicalSize = _celular;
    await t.pump();
    t.view.physicalSize = _medio;
    await t.pump();
    expect(t.takeException(), isNull);
    expect(_textoStatus(t), 'Buscando notícias…');
    espera.complete(s.visaoNoticias);
    await t.pumpAndSettle();
    expect(_textoStatus(t), isNot('Buscando notícias…'));
  });

  group('status', () {
    testWidgets('sem busca feita', (t) async {
      await _montar(t, servicos: _servicos(itens: []));
      expect(_textoStatus(t), 'Google Notícias · ativos do Radar de Ações');
      expect(
        find.text('Nenhuma busca feita ainda. Clique em Atualizar.'),
        findsOneWidget,
      );
    });

    testWidgets('com hora e falhas', (t) async {
      final hora = DateTime(2026, 10, 28, 9, 5).millisecondsSinceEpoch / 1000;
      final s = _servicos(hora: hora, erros: {'WEGE3': 'x', 'PETR4': 'y'});
      await _montar(t, servicos: s);
      expect(
        _textoStatus(t),
        'Atualizado às 09:05 · Google Notícias, últimos 7 dias'
        ' · falha em PETR4, WEGE3',
      );
    });

    testWidgets('com hora e sem falhas', (t) async {
      final hora = DateTime(2026, 10, 28, 14, 30).millisecondsSinceEpoch / 1000;
      await _montar(t, servicos: _servicos(hora: hora));
      expect(
        _textoStatus(t),
        'Atualizado às 14:30 · Google Notícias, últimos 7 dias',
      );
    });

    testWidgets('erro com o texto do Python', (t) async {
      final s = _servicos();
      await _montar(t, servicos: s);
      s.erros['atualizarNoticias'] = ErroValidacao('Sem conexão com o Google');
      await t.tap(find.text('Atualizar'));
      await t.pumpAndSettle();
      expect(
        _textoStatus(t),
        'Não foi possível buscar notícias: Sem conexão com o Google',
      );
    });

    testWidgets('vazio sem ativos no radar', (t) async {
      await _montar(
        t,
        servicos: _servicos(itens: [], radar: const []),
      );
      expect(
        find.text(
          'Adicione ativos no Radar de Ações para ver as notícias deles aqui.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('vazio com filtro', (t) async {
      final hora = DateTime(2026, 10, 28, 9, 5).millisecondsSinceEpoch / 1000;
      await _montar(
        t,
        servicos: _servicos(itens: [_n('a1')], hora: hora),
      );
      await t.tap(find.text('Relevantes'));
      await t.pumpAndSettle();
      expect(
        find.text('Nenhuma notícia nos últimos 7 dias com esse filtro.'),
        findsOneWidget,
      );
    });

    testWidgets('celular: os vazios falam do Radar sem "de Ações"', (t) async {
      await _montar(
        t,
        servicos: _servicos(itens: [], radar: const []),
        tamanho: _celular,
      );
      expect(
        find.text('Adicione ativos no Radar para ver as notícias deles aqui.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('erro ao ler as notícias mantém a lista à vista', (t) async {
    final s = _servicos(itens: [_n('a1')], detalhes: {});
    await _montar(t, servicos: s);
    s.erros['noticias'] = ErroValidacao('disco cheio');
    _estado(t).radarMudou(buscar: false);
    await t.pumpAndSettle();
    expect(_cartao('a1'), findsOneWidget);
    expect(find.text('disco cheio'), findsOneWidget);
  });

  testWidgets('chave Notificar grava a preferência', (t) async {
    final s = _servicos();
    await _montar(t, servicos: s);
    final chave = find.byKey(const Key('chave-notificar'));
    expect(t.widget<Switch>(chave).value, isTrue);
    expect(find.text('Notificar notícias relevantes'), findsOneWidget);
    await t.tap(chave);
    await t.pumpAndSettle();
    expect(t.widget<Switch>(chave).value, isFalse);
    expect(s.preferenciasSalvas!.notificarNoticias, isFalse);
    expect(_estado(t).preferencias.notificarNoticias, isFalse);
  });

  testWidgets('o texto dos relevantes aparece no PC', (t) async {
    await _montar(t, servicos: _servicos());
    expect(find.textContaining('Relevantes: fato relevante'), findsOneWidget);
  });

  group('entrar e sair da aba', () {
    testWidgets('entrar marca lidas, mostra o selo Nova e zera o selo da '
        'aba; sair tira o Nova', (t) async {
      final s = _servicos(itens: [_n('a1')], detalhes: {}, novas: {'a1'});
      await _montar(t, servicos: s, naAba: false);
      s.eventosFalsos.add(EventoNoticias(_visao(naoLidas: 1), const []));
      await t.pumpAndSettle();
      expect(_estado(t).naoLidas, 1);
      expect(s.chamadas, isNot(contains('marcarNoticiasLidas()')));
      _estado(t).irPara(Aba.noticias);
      await t.pumpAndSettle();
      expect(s.chamadas, contains('marcarNoticiasLidas()'));
      expect(_estado(t).naoLidas, 0);
      expect(find.text('Nova'), findsOneWidget);
      // depois de lidas, a visão do serviço não traz mais novas
      s.visaoNoticias = _visao(itens: [_n('a1')]);
      _estado(t).irPara(Aba.radar);
      await t.pumpAndSettle();
      expect(find.text('Nova'), findsNothing);
    });

    testWidgets('entrar atualiza se preciso (sem forçar)', (t) async {
      final s = _servicos();
      await _montar(t, servicos: s, naAba: false);
      expect(s.chamadas, isNot(contains('atualizarNoticias(false)')));
      _estado(t).irPara(Aba.noticias);
      await t.pumpAndSettle();
      expect(s.chamadas, contains('atualizarNoticias(false)'));
    });

    testWidgets('busca que termina com a aba aberta marca lidas de novo', (
      t,
    ) async {
      final s = _servicos();
      await _montar(t, servicos: s);
      final antes = s.chamadas
          .where((c) => c == 'marcarNoticiasLidas()')
          .length;
      s.eventosFalsos.add(EventoNoticias(_visao(naoLidas: 2), const []));
      await t.pumpAndSettle();
      final depois = s.chamadas
          .where((c) => c == 'marcarNoticiasLidas()')
          .length;
      expect(depois, antes + 1);
      expect(_estado(t).naoLidas, 0);
    });

    testWidgets('mudar o radar relê as notícias (ativo removido some)', (
      t,
    ) async {
      final s = _servicos(
        itens: [
          _n('a1'),
          _n('a3', tickers: ['WEGE3']),
        ],
        detalhes: {},
      );
      await _montar(t, servicos: s);
      expect(_cartao('a3'), findsOneWidget);
      s.visaoNoticias = _visao(
        itens: [
          _n('a1'),
          _n('a3', tickers: ['WEGE3']),
        ],
        radar: const [('PETR4', 'Petrobras PN')],
      );
      _estado(t).radarMudou(buscar: false);
      await t.pumpAndSettle();
      expect(_cartao('a3'), findsNothing);
      expect(_cartao('a1'), findsOneWidget);
    });
  });

  group('filtro vindo do gráfico', () {
    testWidgets('"Ver notícias" filtra pelo ativo, e limpar mostra todas', (
      t,
    ) async {
      final s = _servicos();
      await _montar(t, servicos: s, naAba: false);
      _estado(t).verNoticias('WEGE3');
      await t.pumpAndSettle();
      expect(_cartao('a3'), findsOneWidget);
      expect(_cartao('a1'), findsNothing);
      expect(find.byKey(const Key('limpar-filtro-noticias')), findsOneWidget);
      await t.tap(find.byKey(const Key('limpar-filtro-noticias')));
      await t.pumpAndSettle();
      expect(_estado(t).filtroNoticias, isNull);
      expect(_cartao('a1'), findsOneWidget);
      expect(_cartao('a3'), findsOneWidget);
      expect(find.byKey(const Key('limpar-filtro-noticias')), findsNothing);
    });

    testWidgets('escolher outro ativo ou "Todos os ativos" também limpa o '
        'filtro do estado', (t) async {
      await _montar(t, servicos: _servicos(), naAba: false);
      _estado(t).verNoticias('WEGE3');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('menu-ativo-noticias')));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(PopupMenuItem<String>, 'Todos os ativos'),
      );
      await t.pumpAndSettle();
      expect(_estado(t).filtroNoticias, isNull);
      expect(_cartao('a1'), findsOneWidget);
    });

    testWidgets('sair da aba limpa o filtro e a volta mostra todas', (t) async {
      await _montar(t, servicos: _servicos(), naAba: false);
      _estado(t).verNoticias('WEGE3');
      await t.pumpAndSettle();
      expect(_cartao('a1'), findsNothing);
      _estado(t).irPara(Aba.radar);
      await t.pumpAndSettle();
      expect(_estado(t).filtroNoticias, isNull);
      _estado(t).irPara(Aba.noticias);
      await t.pumpAndSettle();
      expect(_cartao('a1'), findsOneWidget);
      expect(_cartao('a3'), findsOneWidget);
    });

    testWidgets('ativo que saiu do radar volta para "Todos os ativos"', (
      t,
    ) async {
      await _montar(t, servicos: _servicos(), naAba: false);
      _estado(t).verNoticias('VALE3');
      await t.pumpAndSettle();
      expect(_estado(t).filtroNoticias, isNull);
      expect(_cartao('a1'), findsOneWidget);
    });

    testWidgets('a tela construída já com o filtro aplica o filtro', (t) async {
      final mostrar = ValueNotifier(false);
      await montarApp(
        t,
        servicos: _servicos(),
        tela: ValueListenableBuilder<bool>(
          valueListenable: mostrar,
          builder: (_, v, _) => v ? const TelaNoticias() : const SizedBox(),
        ),
      );
      Provider.of<EstadoApp>(
        t.element(find.byType(ValueListenableBuilder<bool>).first),
        listen: false,
      ).verNoticias('WEGE3');
      mostrar.value = true;
      await t.pumpAndSettle();
      expect(_cartao('a1'), findsNothing);
      expect(_cartao('a3'), findsOneWidget);
    });
  });
}
