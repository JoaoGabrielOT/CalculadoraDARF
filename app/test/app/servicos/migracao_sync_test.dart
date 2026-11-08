// Migração 2.1-custo-medio na partida com o Sincronizador e o Google reais
// sobre HTTP falso: a migração espera a sincronização (limitada) e nunca
// carimba o marcador, para não reabrir um mês fechado em outro aparelho.

import 'dart:io';

import 'package:calculadoradarf/app/servicos/servicos_locais.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integracoes/apoio/cliente_falso.dart';
import '../apoio/yahoo_falso.dart';

const _sid = 'sid1';
const _email = 'ana@gmail.com';

late ArmazenamentoMemoria disco;
late Repositorio repo;

/// Linhas que a planilha devolve (por aba) e o atraso do `about` (a conexão
/// com o token, primeiro passo da rodada).
Map<String, List<Linha>> remoto = {};
Duration atrasoAbout = Duration.zero;
bool offline = false;
bool aboutFalha = false;
late ClienteFalso cliente;

RespostaFalsa _responder(PedidoGravado p) {
  if (offline) {
    return RespostaFalsa(0, erro: const SocketException('sem rede'));
  }
  final caminho = p.url.path;
  if (caminho.endsWith('/about') && aboutFalha) {
    return RespostaFalsa(
      500,
      json: {
        'error': {'code': 500, 'message': 'falhou'},
      },
      atraso: atrasoAbout,
    );
  }
  if (caminho.endsWith('/about')) {
    return RespostaFalsa(
      200,
      json: {
        'user': {'emailAddress': _email},
      },
      atraso: atrasoAbout,
    );
  }
  if (caminho.contains('/drive/v3/files/')) {
    return RespostaFalsa(200, json: {'id': _sid, 'trashed': false});
  }
  if (caminho.endsWith(':batchUpdate')) {
    return RespostaFalsa(200, json: {'replies': <Object?>[]});
  }
  if (caminho.endsWith('/values:batchGet')) {
    return RespostaFalsa(
      200,
      json: {
        'valueRanges': [
          for (final a in esquemaAbas) {'values': remoto[a.nome] ?? <Linha>[]},
        ],
      },
    );
  }
  if (caminho.endsWith('/spreadsheets/$_sid')) {
    return RespostaFalsa(
      200,
      json: {
        'sheets': [
          for (var i = 0; i < esquemaAbas.length; i++)
            {
              'properties': {
                'sheetId': i,
                'title': esquemaAbas[i].nome,
                'gridProperties': {
                  'rowCount': 1000,
                  'columnCount': esquemaAbas[i].colunas.length,
                },
              },
            },
        ],
      },
    );
  }
  throw StateError('pedido inesperado: ${p.metodo} ${p.url}');
}

Google _google() {
  final http = ClienteHttp(cliente, tempoLimite: const Duration(seconds: 30));
  final sessao = SessaoGoogle(
    http: http,
    armazenamento: disco,
    executar: executarDireto,
  );
  return Google(
    sessao: sessao,
    planilha: PlanilhaGoogle(sessao),
    httpLogin: http,
  );
}

/// Serviços de uma partida, com o token gravado (a conta ainda sem e-mail:
/// ele só vem com a conexão).
ServicosLocais _servicos(
  List<String> ordem, {
  Duration espera = const Duration(seconds: 10),
}) => ServicosLocais(
  repo: repo,
  yahoo: yahooSemRede(),
  conta: _google(),
  abrirUrl: (_) async {},
  atrasoAgendamento: const Duration(hours: 1),
  fazerBackup: () {
    ordem.add('backup:${disco.ler('2026-04.json')}');
    return 'backup/pre';
  },
  esperaSyncMigracao: espera,
);

Lote _compra(String id, {String? origem, String data = '2026-04-02'}) => Lote(
  id: id,
  origem: origem,
  ticker: 'PETR4',
  tipo: 'Ação',
  dataCompra: data,
  qtd: 100,
  preco: 10,
  mod: 50,
);

void main() {
  setUp(() {
    ambiente = Ambiente.fixo(hoje: '2026-05-06', agora: 1770000000.5);
    disco = ArmazenamentoMemoria();
    repo = Repositorio(disco);
    remoto = {};
    atrasoAbout = Duration.zero;
    offline = false;
    aboutFalha = false;
    cliente = ClienteFalso(_responder);
    gravarToken(
      disco,
      TokenGoogle(
        token: 't',
        refreshToken: 'r',
        clientId: 'c.apps.googleusercontent.com',
        clientSecret: 's',
        expiry: DateTime.utc(2099),
      ),
    );
    repo.gravarConfig(Config(planilhas: {_email: _sid}), carimbar: false);
  });

  tearDown(() => ambiente = Ambiente.sistema());

  test('sem e-mail e com um tick em andamento: a migração espera a rodada e '
      'não reabre o mês fechado no outro aparelho', () async {
    // local (2.0): abril aberto, mod 100
    repo.salvar(
      Mes(mes: '2026-04', lotes: [_compra('L1')], mod: 100),
      carimbar: false,
    );
    // outro aparelho: abril fechado (mod 200) e maio marcado com a posição
    final abrFechado = Mes(
      mes: '2026-04',
      fechado: true,
      mod: 200,
      lotes: [_compra('L1')],
    );
    abrFechado.resumo = apurar(abrFechado).resumo;
    final maio = Mes(
      mes: '2026-05',
      mod: 210,
      lotes: [_compra('L1~2026-05', origem: 'L1')],
      metodo: metodoCustoMedio,
      posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1000.3)},
      prejuizoAnterior: PrejuizoAcumulado(comum: 7.5),
    );
    remoto = montarLinhas([abrFechado, maio], Config());
    atrasoAbout = const Duration(milliseconds: 300);

    final ordem = <String>[];
    final s = _servicos(ordem);
    expect(_google().email, isNull);
    // o tick do timer já está conectando com o token
    final tick = s.tickSync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await s.iniciar();

    // o backup veio antes de qualquer gravação local (abril ainda aberto)
    expect(ordem.single, contains('"fechado": false'));
    // a migração viu os dados mesclados: abril fechado, sem marcador
    final abr = repo.carregar('2026-04');
    expect(abr.fechado, isTrue);
    expect(abr.metodo, isNull);
    expect(abr.mod, 200.0);
    // maio, o corte do outro aparelho, com a posição e o prejuízo dele
    final mai = repo.carregar('2026-05');
    expect(mai.metodo, metodoCustoMedio);
    expect(mai.posicaoInicial!['PETR4']!.custo, 1000.3);
    expect(mai.prejuizoAnterior!.comum, 7.5);
    expect(mai.mod, 210.0);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
    await tick;
    await s.encerrar();
  });

  test('sincronização demorada: segue depois do limite, sem carimbo', () async {
    repo.salvar(
      Mes(mes: '2026-04', lotes: [_compra('L1')], mod: 100),
      carimbar: false,
    );
    atrasoAbout = const Duration(milliseconds: 800);
    final ordem = <String>[];
    final s = _servicos(ordem, espera: const Duration(milliseconds: 200));
    final relogio = Stopwatch()..start();
    await s.iniciar();
    expect(relogio.elapsed, lessThan(const Duration(milliseconds: 700)));
    final abr = repo.carregar('2026-04');
    expect(abr.metodo, metodoCustoMedio);
    expect(abr.mod, 100.0);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
    // a rodada atrasada termina depois e não tira o marcador
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    expect(repo.carregar('2026-04').metodo, metodoCustoMedio);
    await s.encerrar();
  });

  test('instalação nova e depois login com o mês remoto marcado', () async {
    final abr = Mes(
      mes: '2026-04',
      mod: 200,
      darfAnterior: 4.5,
      lotes: [_compra('L1~2026-04', origem: 'L1', data: '2026-03-02')],
      metodo: metodoCustoMedio,
      posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1000.3)},
      prejuizoAnterior: PrejuizoAcumulado(comum: 12.0, dayTrade: 3.0),
    );
    remoto = montarLinhas([abr], Config());

    // primeira abertura: nenhum mês, nada criado, nada registrado
    final ordem = <String>[];
    final s1 = _servicos(ordem);
    await s1.iniciar();
    expect(ordem, isEmpty);
    expect(repo.listarMeses(), isEmpty);
    expect(repo.lerConfig().migracoes, isEmpty);

    // a sincronização traz o mês remoto, intacto
    await s1.tickSync();
    final lido = repo.carregar('2026-04');
    expect(lido.metodo, metodoCustoMedio);
    expect(lido.posicaoInicial!['PETR4']!.custo, 1000.3);
    expect(lido.prejuizoAnterior!.toJson(), {'comum': 12.0, 'day_trade': 3.0});
    expect(lido.darfAnterior, 4.5);
    await s1.encerrar();

    // próxima abertura: backup, registro e o mês como veio
    final antes = disco.ler('2026-04.json');
    final s2 = _servicos(ordem);
    await s2.iniciar();
    expect(ordem, hasLength(1));
    expect(disco.ler('2026-04.json'), antes);
    expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
    await s2.encerrar();
  });

  group('corte do aparelho que migrou sem rede', () {
    // local: março aberto (2.0, mod 100). Outro aparelho, ainda na versão
    // antiga: março fechado sem marcador (mod 200) e abril aberto, sem
    // marcador, com a cópia levada.
    late Mes marFechado;
    late Mes abril;

    setUp(() {
      repo.salvar(
        Mes(
          mes: '2026-03',
          lotes: [_compra('L1', data: '2026-03-02')],
          mod: 100,
        ),
        carimbar: false,
      );
      marFechado = Mes(
        mes: '2026-03',
        fechado: true,
        mod: 200,
        lotes: [_compra('L1', data: '2026-03-02')],
      );
      marFechado.resumo = apurar(marFechado).resumo;
      abril = Mes(
        mes: '2026-04',
        mod: 210,
        lotes: [_compra('L1~2026-04', origem: 'L1', data: '2026-03-02')],
      );
      remoto = montarLinhas([marFechado, abril], Config());
    });

    List<Object?> resumoMarco(Iterable<Mes> meses) => montarLinhas(
      meses.toList(),
      Config(),
    )['Resumo']!.firstWhere((l) => l[0] == '03/2026').sublist(0, 13);

    bool marcadorNaPlanilha() => cliente.pedidos.any(
      (p) =>
          p.url.path.endsWith(':batchUpdate') &&
          p.texto.contains('custo_medio'),
    );

    test('migra sem rede; a sincronização fecha março como veio e o corte '
        'passa para abril', () async {
      offline = true;
      final s = _servicos(<String>[]);
      await s.iniciar();
      // sem rede: março marcado, sem carimbo
      expect(repo.carregar('2026-03').metodo, metodoCustoMedio);
      expect(repo.carregar('2026-03').mod, 100.0);
      expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);

      offline = false;
      await s.tickSync();
      // março fechado no outro aparelho continua fechado, Resumo idêntico
      final mar = repo.carregar('2026-03');
      expect(mar.fechado, isTrue);
      expect(mar.metodo, isNull);
      expect(mar.mod, 200.0);
      expect(
        resumoMarco(repo.carregarMeses().values),
        resumoMarco([marFechado]),
      );
      // o corte foi reaplicado em abril, sem carimbo, e subiu na mesma rodada
      final abr = repo.carregar('2026-04');
      expect(abr.metodo, metodoCustoMedio);
      expect(abr.posicaoInicial!['PETR4']!.qtd, 100);
      expect(abr.mod, 210.0);
      expect(marcadorNaPlanilha(), isTrue);
      await s.encerrar();
    });

    test('sincronização além do limite: a rodada em voo termina, não começa '
        'outra, e depois do tick abril está marcado', () async {
      atrasoAbout = const Duration(milliseconds: 600);
      final s = _servicos(
        <String>[],
        espera: const Duration(milliseconds: 150),
      );
      await s.iniciar();
      expect(repo.carregar('2026-03').metodo, metodoCustoMedio);
      expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      // uma só conexão: o limite não deixou outra rodada começar
      expect(
        cliente.pedidos.where((p) => p.url.path.endsWith('/about')),
        hasLength(1),
      );
      await s.tickSync();
      final mar = repo.carregar('2026-03');
      expect(mar.fechado, isTrue);
      expect(mar.metodo, isNull);
      expect(repo.carregar('2026-04').metodo, metodoCustoMedio);
      expect(repo.carregar('2026-04').mod, 210.0);
      await s.encerrar();
    });
  });

  test(
    'rodada em voo que falha depois do limite: nenhuma outra começa',
    () async {
      repo.salvar(
        Mes(mes: '2026-04', lotes: [_compra('L1')], mod: 100),
        carimbar: false,
      );
      atrasoAbout = const Duration(milliseconds: 500);
      aboutFalha = true;
      final s = _servicos(
        <String>[],
        espera: const Duration(milliseconds: 150),
      );
      final tick = s.tickSync();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await s.iniciar();
      expect(repo.carregar('2026-04').metodo, metodoCustoMedio);
      await tick;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(
        cliente.pedidos.where((p) => p.url.path.endsWith('/about')),
        hasLength(1),
      );
      await s.encerrar();
    },
  );
}
