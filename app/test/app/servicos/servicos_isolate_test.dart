import 'dart:io';
import 'dart:isolate';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/parametros.dart';
import 'package:calculadoradarf/app/servicos/servicos_isolate.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../apoio/servicos_eco.dart';

/// Cliente de nível superior (enviável ao isolate): toda rede responde 503.
http.Client clienteSemRede() => MockClient((_) async => http.Response('', 503));

ParametrosServicos _eco() => ParametrosServicos(
  pastaDados: '',
  pastaTemporaria: '',
  windows: true,
  criarServicos: criarServicosEco,
  timers: false,
);

final _tema = Preferencias(tema: TemaVisual.terminal, ordemRadar: 'x');

void main() {
  late ServicosIsolate s;
  late Future<bool> Function(Uri) abrir;
  late List<Uri> abertas;

  setUp(() async {
    abertas = [];
    abrir = (u) async {
      abertas.add(u);
      return true;
    };
    s = await ServicosIsolate.criar(_eco(), abrirUrl: (u) => abrir(u));
  });

  tearDown(() async {
    try {
      await s.encerrar();
    } on StateError {
      // já encerrado pelo teste
    }
  });

  test('cada método do contrato chega ao isolate e volta', () async {
    final ini = await s.iniciar();
    expect(ini.mesInicial, '2026-10');
    expect(ini.erroConfig, 'eco');
    expect(ini.preferencias.ordemRadar, 'eco');
    expect(ini.temCredencial, isTrue);

    final aviso = s.eventos.firstWhere((e) => e is EventoAviso);
    await s.salvarPreferencias(_tema);
    final ev = await aviso as EventoAviso;
    expect(ev.texto, 'terminal|x');

    expect(await s.mesesComDados(amigo: 'a'), ['m:a']);
    expect(await s.mesInicial(amigo: 'b'), 'inicial:b');
    expect((await s.carregarMes('2026-09', amigo: 'c')).mes, '2026-09');
    expect((await s.carregarMes('2026-09', amigo: 'c')).amigo, 'c');
    final sug = await s.sugestoesTicker('2026-08', soCustodia: true);
    expect(sug.tickers, ['2026-08', 'true']);
    const compra = NovaCompra(
      ticker: 'PETR4',
      dataCompra: '2026-10-01',
      qtd: 7,
      preco: 3,
    );
    const venda = NovaVenda(loteId: 'L9', data: '2026-10-02', qtd: 4, preco: 5);
    expect((await s.registrarCompra('2026-10', compra)).mes, '2026-10/PETR4');
    expect((await s.editarCompra('2026-10', 'L1', compra)).mes, '2026-10/L1/7');
    expect((await s.excluirCompra('2026-10', 'L2')).mes, '2026-10/L2');
    final vr = await s.registrarVenda('2026-10', venda);
    expect(vr.mesGravado, 'L9');
    expect(vr.aviso, '2026-10-02|4|5.0');
    expect((await s.editarVenda('2026-10', 'V1', venda)).mes, '2026-10/V1/4');
    expect((await s.excluirVenda('2026-10', 'V2')).mes, '2026-10/V2');
    expect(await s.mesesSemVendaRetroativa('2026-07'), {'2026-07'});
    expect(await s.reservadoEmMetas('abcd'), 4);
    expect(
      (await s.prepararFechamento('2026-10')).bloqueio,
      'bloqueio 2026-10',
    );
    expect((await s.fecharMes('2026-10')).mensagem, 'fechou 2026-10');

    expect((await s.caixa(amigo: 'x')).resumo.saldoBase, 123);
    expect((await s.alterarSaldo(ModoSaldo.aporte, 10)).resumo.saldoBase, 11);

    expect((await s.conta()).email, 'eco@exemplo.com');
    await s.cancelarLogin();
    await s.sair();
    await s.sincronizarAgora();
    expect((await s.amigos()).single.email, 'a@exemplo.com');
    await s.adicionarAmigo('ok@exemplo.com');
    await s.removerAmigo('ok@exemplo.com');
    expect((await s.carregarAmigo('z@exemplo.com')).email, 'z@exemplo.com');
    await s.esquecerAmigo();

    expect((await s.radar(amigo: 'r')).custodia, {'x:r'});
    expect((await s.adicionarRadar('VALE3')).ticker, 'VALE3');
    expect(await s.importarRadar(radarImportar()), 2);
    await s.removerRadar('VALE3');
    await s.reordenarRadar(['A', 'B']);
    await s.limparCacheCotacoes();
    final cot = await s.cotacao('PETR4', nome: 'Petro');
    expect(cot, isA<CotacaoErro>());
    expect((cot as CotacaoErro).mensagem, 'eco:Petro');
    final g = await s.grafico('PETR4', '5D');
    expect((g.ticker, g.periodo, g.pontos.single), ('PETR4', '5D', (1, 2.5)));
    expect(await s.precosCarteira({'ABC', 'DEFG'}), {
      'ABC': 3.0,
      'DEFG': 4.0,
      'nulo': null,
    });
    final ca = await s.cotacoesAtuais({'ABC'});
    expect(ca['ABC']!.preco, 3.0);
    expect(ca['ABC']!.fonte, 'Yahoo');
    expect(ca['ABC']!.hora.horaMinuto, '19:40');
    expect(ca['nulo'], isNull);
    final pos = await s.posicoes('2026-10');
    expect((pos.dataCorte, pos.corrente), ('2026-10-28', true));
    expect(await s.precoVenda('PETR4', '2026-10-01'), (
      1.5,
      'PETR4@2026-10-01',
    ));
    expect((await s.metas()).ativas, 7);
    expect((await s.sugestoesMetas()).ativos, isEmpty);
    expect((await s.calcularPrecoAlvo('L1', 12, 3.5)).preco, 12);
    expect((await s.projetarPreco('L1', 1, 8.5)).lucroAposImposto, 8.5);
    expect(await s.parceiraOco('L1', 'nenhuma'), isNull);
    expect((await s.parceiraOco('L1', 'x'))!.id, 'oco');
    final alvo = await s.criarMetaAlvo(
      'L1',
      5,
      9,
      lucroDesejado: 2,
      ocoCom: 'M1',
    );
    expect((alvo.id, alvo.qtd, alvo.precoAlvo), ('alvo:M1:2.0', 5, 9.0));
    final stop = await s.criarStop(
      'L1',
      6,
      7,
      movel: true,
      ocoCom: 'M2',
      precoAtual: 8,
      sugestao: {'a': 1},
    );
    expect(stop.id, 'stop:true:M2:8.0');
    await s.cancelarMeta('M1');
    expect(await s.verificarMetas(), isA<VerificacaoFalhou>());

    expect((await s.noticias()).naoLidas, 1);
    expect((await s.atualizarNoticias(forcar: true)).naoLidas, 2);
    expect((await s.atualizarNoticias()).naoLidas, 3);
    await s.marcarNoticiasLidas();
    final logo = (await s.logo('PETR4'))!;
    expect(logo.bytes, orderedEquals([1, 2, 3]));
    expect(logo.svg, isTrue);
    expect(await s.favicon(noticiaComId('ab')), [97, 98]);
    expect(await s.imagemNoticia('https://exemplo.com/i.jpg'), isNull);
    final info = (await s.verificarAtualizacao())!;
    expect(info.versao, '9.9.9');
    expect(await s.baixarAtualizacao(info), 'baixou 9.9.9');
    await s.cancelarDownload();
  });

  test('ErroValidacao volta com o mesmo tipo e mensagem', () async {
    try {
      await s.adicionarAmigo('invalido@exemplo.com');
      fail('devia lançar');
    } on ErroValidacao catch (e, pilha) {
      expect(e.mensagem, 'Amigo inválido.');
      expect(pilha.toString(), contains('adicionarAmigo'));
    }
  });

  test('ErroGoogle mantém status', () async {
    await expectLater(
      s.removerAmigo('falha@exemplo.com'),
      throwsA(
        isA<ErroGoogle>()
            .having((e) => e.mensagem, 'mensagem', 'O Google recusou.')
            .having((e) => e.status, 'status', 403),
      ),
    );
  });

  test('eventos emitidos no isolate chegam ao stream', () async {
    final primeiro = s.eventos.first;
    await s.sincronizarAgora();
    final e = await primeiro.timeout(const Duration(seconds: 5));
    expect(e, isA<EventoAviso>());
    expect((e as EventoAviso).texto, 'sincronizou');
  });

  test(
    'AbrirUrl: interface responde false → ErroGoogle; true → completa',
    () async {
      await s.conectar();
      expect(abertas.single.toString(), 'https://exemplo.com/login');

      abrir = (_) async => false;
      await expectLater(
        s.conectar(),
        throwsA(
          isA<ErroGoogle>().having(
            (e) => e.mensagem,
            'mensagem',
            'Não foi possível abrir o navegador.',
          ),
        ),
      );
    },
  );

  test('AbrirUrl: falha ao abrir na interface chega como ErroGoogle', () async {
    abrir = (_) async => throw StateError('sem navegador');
    await expectLater(s.conectar(), throwsA(isA<ErroGoogle>()));
  });

  test(
    'encerrar fecha o isolate e chamadas depois lançam StateError',
    () async {
      final fim = s.eventos.drain<void>();
      await s.encerrar();
      await fim.timeout(const Duration(seconds: 5));
      await expectLater(
        s.conta(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Serviços encerrados.',
          ),
        ),
      );
    },
  );

  test('evento emitido durante criarServicos chega a quem assina depois, '
      'na ordem', () async {
    final cedo = await ServicosIsolate.criar(
      ParametrosServicos(
        pastaDados: '',
        pastaTemporaria: 'cedo',
        windows: true,
        criarServicos: criarServicosEco,
        timers: false,
      ),
      abrirUrl: (_) async => true,
    );
    try {
      await cedo.conta(); // a interface já conversou com o isolate
      // dois assinantes juntos: cada um recebe exatamente os dois, sem repetir
      final a = <String>[], b = <String>[];
      cedo.eventos.listen((e) => a.add((e as EventoAviso).texto));
      cedo.eventos.listen((e) => b.add((e as EventoAviso).texto));
      await Future<void>.delayed(Duration.zero);
      await cedo.conta();
      await Future<void>.delayed(Duration.zero);
      expect(a, ['primeiro', 'segundo']);
      expect(b, ['primeiro', 'segundo']);

      // quem assina depois da descarga não recebe o passado (o buffer só vale
      // até a primeira assinatura)
      final tarde = <String>[];
      cedo.eventos.listen((e) => tarde.add((e as EventoAviso).texto));
      await Future<void>.delayed(Duration.zero);
      expect(tarde, isEmpty);
    } finally {
      await cedo.encerrar();
    }
  });

  test('buffer de eventos guarda só os 256 últimos, na ordem', () async {
    final muitos = await ServicosIsolate.criar(
      ParametrosServicos(
        pastaDados: '',
        pastaTemporaria: 'muitos',
        windows: true,
        criarServicos: criarServicosEco,
        timers: false,
      ),
      abrirUrl: (_) async => true,
    );
    try {
      await muitos.conta();
      final vistos = <String>[];
      muitos.eventos.listen((e) => vistos.add((e as EventoAviso).texto));
      await Future<void>.delayed(Duration.zero);
      expect(vistos, [for (var i = 44; i < 300; i++) '$i']);
    } finally {
      await muitos.encerrar();
    }
  });

  test(
    'encerrar em cache conclui normalmente se o isolate morre no meio',
    () async {
      await s.removerAmigo('morreaoencerrar@exemplo.com');
      await s.encerrar();
      await s.encerrar();
    },
  );

  test('erro não enviável chega com o texto, sem pendurar o pedido', () async {
    await expectLater(
      s
          .adicionarAmigo('naoenviavel@exemplo.com')
          .timeout(const Duration(seconds: 5)),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'texto',
          contains('texto do erro'),
        ),
      ),
    );
    expect((await s.conta()).email, 'eco@exemplo.com');
  });

  test('argumento não enviável falha o pedido e o proxy continua', () async {
    final porta = ReceivePort();
    await expectLater(
      s.criarStop('L1', 1, 1, sugestao: {'porta': porta}),
      throwsA(anything),
    );
    porta.close();
    expect((await s.conta()).email, 'eco@exemplo.com');
  });

  test('pedido em voo quando o isolate morre de verdade falha', () async {
    final preso = s.removerAmigo('pendura@exemplo.com');
    final morre = s.adicionarAmigo('morre@exemplo.com');
    Matcher encerrado() => throwsA(
      isA<StateError>().having(
        (e) => e.message,
        'message',
        'Serviços encerrados.',
      ),
    );
    await Future.wait([
      expectLater(preso, encerrado()),
      expectLater(morre, encerrado()),
    ]).timeout(const Duration(seconds: 10));
    await expectLater(s.conta(), encerrado());
  });

  test('erro assíncrono solto vira aviso e os serviços seguem vivos', () async {
    final aviso = s.eventos
        .firstWhere((e) => e is EventoAviso && e.texto.contains('erro solto'))
        .timeout(const Duration(seconds: 5));
    await s.adicionarAmigo('solta@exemplo.com');
    final e = await aviso as EventoAviso;
    expect(e.texto, contains('erro solto do eco'));
    expect((await s.conta()).email, 'eco@exemplo.com');
  });

  test('falha de montagem não enviável chega com o texto real', () async {
    await expectLater(
      ServicosIsolate.criar(
        ParametrosServicos(
          pastaDados: '',
          pastaTemporaria: '',
          windows: true,
          criarServicos: criarServicosFalha,
          timers: false,
        ),
        abrirUrl: (_) async => true,
      ).timeout(const Duration(seconds: 5)),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'texto',
          contains('texto da montagem'),
        ),
      ),
    );
  });

  test(
    'pedido em voo quando encerrar é chamado falha com StateError',
    () async {
      final preso = s.removerAmigo('pendura@exemplo.com');
      final falha = expectLater(
        preso,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Serviços encerrados.',
          ),
        ),
      );
      await s.encerrar();
      await falha;
    },
  );

  test('encerrar concorrente é idempotente', () async {
    await Future.wait([s.encerrar(), s.encerrar()]);
    await s.encerrar();
  });

  test('ErroAtualizacao e erro de rede atravessam com tipo e texto', () async {
    await expectLater(
      s.cotacao('REDE'),
      throwsA(
        isA<ErroConexao>().having(
          (e) => e.mensagem,
          'mensagem',
          'Sem conexão com o Yahoo.',
        ),
      ),
    );
    const info = InfoAtualizacao(
      versao: 'erro',
      notas: '',
      url: 'https://exemplo.com/a.exe',
      tamanho: 1,
      sha256: '',
    );
    await expectLater(
      s.baixarAtualizacao(info),
      throwsA(
        isA<ErroAtualizacao>().having(
          (e) => e.mensagem,
          'mensagem',
          'Resposta inválida do GitHub.',
        ),
      ),
    );
  });

  test(
    'download cancelado: cancelarDownload chega durante o download',
    () async {
      const info = InfoAtualizacao(
        versao: 'longo',
        notas: '',
        url: 'https://exemplo.com/a.exe',
        tamanho: 1,
        sha256: '',
      );
      final progresso = s.eventos
          .firstWhere((e) => e is EventoProgresso)
          .timeout(const Duration(seconds: 5));
      final baixando = s.baixarAtualizacao(info);
      final falha = expectLater(
        baixando,
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Atualização cancelada.',
          ),
        ),
      );
      await progresso; // o download já começou no isolate
      await s.cancelarDownload();
      await falha;
    },
  );

  group('serviços reais', () {
    late Directory pasta;

    setUp(() => pasta = Directory.systemTemp.createTempSync('isolate_'));

    tearDown(() => pasta.deleteSync(recursive: true));

    test(
      'serviços reais num isolate com pasta temporária e cliente sem rede',
      () async {
        final real = await ServicosIsolate.criar(
          ParametrosServicos(
            pastaDados: '${pasta.path}/dados',
            pastaTemporaria: pasta.path,
            windows: true,
            criarCliente: clienteSemRede,
            timers: false,
          ),
          abrirUrl: (_) async => true,
        );
        try {
          final ini = await real.iniciar();
          expect(ini.erroConfig, isNull);
          expect(
            pasta
                .listSync(recursive: true)
                .whereType<File>()
                .map((f) => f.uri.pathSegments.last),
            isEmpty,
          );

          final v = await real.registrarCompra(
            '2026-10',
            const NovaCompra(
              ticker: 'PETR4',
              dataCompra: '2026-10-01',
              qtd: 100,
              preco: 30,
            ),
          );
          expect(v.dados.lotes.single.ticker, 'PETR4');
          expect(File('${pasta.path}/dados/2026-10.json').existsSync(), isTrue);

          expect(await real.cotacao('PETR4'), isA<CotacaoErro>());

          // as fábricas de notícias e do atualizador existem no isolate
          expect((await real.noticias()).itens, isEmpty);
          await expectLater(
            real.verificarAtualizacao(),
            throwsA(isNot(isA<StateError>())),
          );
          expect((await real.conta()).email, isNull);
        } finally {
          await real.encerrar();
        }
      },
    );
  });

  group('TimersServicos', () {
    test('erro em tickSync, metas ou notícias não derruba os timers', () async {
      var sync = 0, metas = 0, noticias = 0;
      final t = TimersServicos(
        sync: () async {
          sync++;
          throw ErroValidacao('sync');
        },
        metas: () async {
          metas++;
          throw StateError('metas');
        },
        noticias: () {
          noticias++;
          throw const FormatException('noticias');
        },
        intervaloSync: const Duration(milliseconds: 20),
        primeiraMetas: const Duration(milliseconds: 10),
        intervaloMetas: const Duration(milliseconds: 20),
        primeiraNoticias: const Duration(milliseconds: 10),
        intervaloNoticias: const Duration(milliseconds: 20),
      )..iniciar();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      t.cancelar();
      final vistos = (sync, metas, noticias);
      expect(vistos.$1, greaterThan(2));
      expect(vistos.$2, greaterThan(2));
      expect(vistos.$3, greaterThan(2));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect((sync, metas, noticias), vistos, reason: 'cancelar para tudo');
    });

    test('o primeiro tick de sincronização é na hora', () async {
      var sync = 0;
      final t = TimersServicos(
        sync: () async => sync++,
        metas: () async {},
        noticias: () async {},
        intervaloSync: const Duration(hours: 1),
        primeiraMetas: const Duration(hours: 1),
        intervaloMetas: const Duration(hours: 1),
        primeiraNoticias: const Duration(hours: 1),
        intervaloNoticias: const Duration(hours: 1),
      )..iniciar();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      t.cancelar();
      expect(sync, 1);
    });

    test('padrões: 60 s no Windows, 30 s no Android; metas 2,5 s/60 s; '
        'notícias 8 s/60 s', () {
      expect(intervaloSyncPadrao(windows: true), const Duration(seconds: 60));
      expect(intervaloSyncPadrao(windows: false), const Duration(seconds: 30));
      expect(primeiraMetasPadrao, const Duration(milliseconds: 2500));
      expect(intervaloMetasPadrao, const Duration(seconds: 60));
      expect(primeiraNoticiasPadrao, const Duration(seconds: 8));
      expect(intervaloNoticiasPadrao, const Duration(seconds: 60));
    });
  });
}

List<ItemRadar> radarImportar() => [
  ItemRadar(ticker: 'A', desde: '2026-10-01'),
  ItemRadar(ticker: 'B', desde: '2026-10-01'),
];

Noticia noticiaComId(String id) => Noticia(
  id: id,
  titulo: 't',
  link: 'l',
  fonte: 'f',
  fonteUrl: '',
  data: 1,
  tickers: const [],
  temas: const [],
);
