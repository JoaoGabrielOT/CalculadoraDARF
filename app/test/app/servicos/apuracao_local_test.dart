import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_locais.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/conta_falsa.dart';
import '../apoio/yahoo_falso.dart';

class _ArmazenamentoQueFalha extends ArmazenamentoMemoria {
  @override
  String? ler(String nome) {
    if (nome == 'config.json') {
      throw const FormatException('bytes UTF-8 inválidos');
    }
    return super.ler(nome);
  }
}

late ArmazenamentoMemoria disco;
late Repositorio repo;
late ServicosLocais servicos;
late List<EventoServico> eventos;

/// Agendamentos vistos pela conta conectada (o stream entrega depois de um
/// ciclo de eventos).
Future<int> agendamentos() async {
  await Future<void>.delayed(Duration.zero);
  return eventos
      .whereType<EventoConta>()
      .where((e) => e.conta.status == StatusSync.pendente)
      .length;
}

Lote compra(
  String id, {
  String ticker = 'PETR4',
  String tipo = 'Ação',
  String data = '2026-10-05',
  int qtd = 100,
  double preco = 10,
  String? origem,
  List<Venda>? vendas,
}) => Lote(
  id: id,
  origem: origem,
  ticker: ticker,
  tipo: tipo,
  dataCompra: data,
  qtd: qtd,
  preco: preco,
  vendas: vendas,
);

void gravarMes(String mes, List<Lote> lotes, {bool fechado = false}) =>
    repo.salvar(Mes(mes: mes, lotes: lotes, fechado: fechado));

Future<void> espera(Future<Object?> f, String mensagem) async {
  await expectLater(
    f,
    throwsA(
      isA<ErroValidacao>().having((e) => e.mensagem, 'mensagem', mensagem),
    ),
  );
}

void main() {
  setUp(() {
    ambiente = Ambiente.fixo();
    disco = ArmazenamentoMemoria();
    repo = Repositorio(disco);
    // com a conta conectada cada agendamento emite um EventoConta pendente;
    // o atraso longo mantém a sincronização fora dos testes
    servicos = ServicosLocais(
      repo: repo,
      yahoo: yahooSemRede(),
      conta: ContaFalsa(email: 'ana@gmail.com'),
      abrirUrl: (_) async {},
      atrasoAgendamento: const Duration(hours: 1),
    );
    eventos = [];
    servicos.eventos.listen(eventos.add);
  });

  tearDown(() async => servicos.encerrar());

  group('inicialização e preferências', () {
    test(
      'iniciar: corrige tipos, marca pendente e devolve o mês inicial',
      () async {
        gravarMes('2026-10', [compra('L1', ticker: 'AAPL34', tipo: 'Ação')]);
        expect(repo.lerConfig().pendente, isFalse);
        final e = await servicos.iniciar();
        expect(repo.carregar('2026-10').lotes.single.tipo, 'BDR');
        expect(repo.lerConfig().pendente, isTrue);
        expect(e.mesInicial, repo.mesInicial());
        expect(e.mesesComDados, ['2026-10']);
        expect(e.erroConfig, isNull);
        expect(e.preferencias.tema, TemaVisual.automatico);
        expect(e.preferencias.notificarNoticias, isTrue);
        expect(e.preferencias.ordemRadar, 'manual');
      },
    );

    group('migração 2.1-custo-medio', () {
      ServicosLocais criar(String Function() backup) => ServicosLocais(
        repo: repo,
        yahoo: yahooSemRede(),
        conta: ContaFalsa(),
        abrirUrl: (_) async {},
        atrasoAgendamento: const Duration(hours: 1),
        fazerBackup: backup,
      );

      test('iniciar faz o backup, marca o mês aberto e registra', () async {
        gravarMes('2026-09', [compra('L0', data: '2026-09-01')], fechado: true);
        gravarMes('2026-10', [compra('L1', origem: 'L0', data: '2026-09-01')]);
        final antes = disco.ler('2026-09.json');
        var backups = 0;
        final s = criar(() {
          backups++;
          return 'backup/pre';
        });
        final ev = <EventoServico>[];
        s.eventos.listen(ev.add);
        final e = await s.iniciar();
        expect(backups, 1);
        expect(e.mesInicial, '2026-10');
        expect(repo.carregar('2026-10').metodo, metodoCustoMedio);
        expect(repo.carregar('2026-10').posicaoInicial!['PETR4']!.qtd, 100);
        expect(disco.ler('2026-09.json'), antes);
        expect(repo.lerConfig().migracoes, [idMigracaoCustoMedio]);
        // a coluna 14 sobe na próxima sincronização
        expect(repo.lerConfig().pendente, isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(ev.whereType<EventoMigracao>(), isEmpty);
        await s.iniciar();
        expect(backups, 1);
        await s.encerrar();
      });

      test(
        'backup que falha: nada marcado e EventoMigracao com o aviso',
        () async {
          gravarMes('2026-10', [compra('L1')]);
          final antes = disco.ler('2026-10.json');
          final s = criar(() => throw Exception('arquivo em uso'));
          final ev = <EventoServico>[];
          s.eventos.listen(ev.add);
          await s.iniciar();
          await Future<void>.delayed(Duration.zero);
          expect(disco.ler('2026-10.json'), antes);
          expect(repo.lerConfig().migracoes, isEmpty);
          final aviso = ev.whereType<EventoMigracao>().single;
          expect(aviso.titulo, tituloBackupFalhou);
          expect(aviso.texto, textoBackupFalhou);
          expect(
            textoBackupFalhou,
            'Não foi possível fazer o backup dos dados; o cálculo por custo '
            'médio não foi ativado. Feche outros programas que usem a pasta de '
            'dados e abra o app de novo.',
          );
          await s.encerrar();
        },
      );

      test(
        'o backup vem antes da correção dos tipos (primeira gravação)',
        () async {
          gravarMes('2026-10', [compra('L1', ticker: 'AAPL34', tipo: 'Ação')]);
          String? noBackup;
          final s = criar(() {
            noBackup = disco.ler('2026-10.json');
            return 'backup/pre';
          });
          await s.iniciar();
          expect(noBackup, contains('"Ação"'));
          expect(repo.carregar('2026-10').lotes.single.tipo, 'BDR');
          await s.encerrar();
        },
      );

      test('mês marcado na partida mantém o mod (sem carimbo)', () async {
        gravarMes('2026-10', [compra('L1')]);
        final mod = repo.carregar('2026-10').mod;
        ambiente = Ambiente.fixo(agora: 1790000000.5);
        final s = criar(() => 'backup/pre');
        await s.iniciar();
        expect(repo.carregar('2026-10').metodo, metodoCustoMedio);
        expect(repo.carregar('2026-10').mod, mod);
        await s.encerrar();
      });

      test(
        'mês ilegível antes do corte: nada marcado e o aviso lista o pulado',
        () async {
          disco.gravar(
            '2026-09.json',
            '{"mes": "2026-09", "lotes": [{"qtd": 1.5}]}',
          );
          gravarMes('2026-10', [compra('L1')]);
          final s = criar(() => 'backup/pre');
          final ev = <EventoServico>[];
          s.eventos.listen(ev.add);
          await s.iniciar();
          await Future<void>.delayed(Duration.zero);
          expect(repo.carregar('2026-10').metodo, isNull);
          expect(repo.lerConfig().migracoes, isEmpty);
          final aviso = ev.whereType<EventoMigracao>().single;
          expect(aviso.titulo, tituloMesesIlegiveis);
          expect(aviso.texto, textoMigracaoAdiada(['2026-09']));
          await s.encerrar();
        },
      );

      test(
        'mês ilegível depois do corte: aviso de que ficou de fora',
        () async {
          gravarMes('2026-10', [compra('L1')]);
          disco.gravar(
            '2026-11.json',
            '{"mes": "2026-11", "lotes": [{"qtd": 1.5}]}',
          );
          final s = criar(() => 'backup/pre');
          final ev = <EventoServico>[];
          s.eventos.listen(ev.add);
          await s.iniciar();
          await Future<void>.delayed(Duration.zero);
          expect(repo.carregar('2026-10').metodo, metodoCustoMedio);
          final aviso = ev.whereType<EventoMigracao>().single;
          expect(aviso.texto, textoMesesIlegiveis(['2026-11']));
          await s.encerrar();
        },
      );

      test('carga com a migração registrada e nenhum mês marcado reaplica o '
          'corte, sem carimbo', () async {
        gravarMes('2026-09', [compra('L0', data: '2026-09-01')], fechado: true);
        gravarMes('2026-10', [compra('L1', origem: 'L0', data: '2026-09-01')]);
        final cfg = repo.lerConfig()..migracoes = [idMigracaoCustoMedio];
        repo.gravarConfig(cfg);
        final mod = repo.carregar('2026-10').mod;
        ambiente = Ambiente.fixo(agora: 1790000000.5);
        final v = await servicos.carregarMes('2026-10');
        expect(v.dados.metodo, metodoCustoMedio);
        expect(v.apuracao.metodo, metodoCustoMedio);
        expect(repo.carregar('2026-10').metodo, metodoCustoMedio);
        expect(repo.carregar('2026-10').mod, mod);
        expect(repo.carregar('2026-09').metodo, isNull);
      });

      test(
        'instalação nova: sem backup, sem mês criado, sem registro',
        () async {
          var backups = 0;
          final s = criar(() {
            backups++;
            return 'backup/pre';
          });
          await s.iniciar();
          expect(backups, 0);
          expect(repo.listarMeses(), isEmpty);
          expect(repo.lerConfig().migracoes, isEmpty);
          await s.encerrar();
        },
      );

      test('config ilegível: a migração não roda', () async {
        disco.gravar('config.json', '{');
        gravarMes('2026-10', [compra('L1')]);
        var backups = 0;
        final s = criar(() {
          backups++;
          return 'backup/pre';
        });
        await s.iniciar();
        expect(backups, 0);
        expect(repo.carregar('2026-10').metodo, isNull);
        await s.encerrar();
      });
    });

    test('sem fazerBackup (testes) a migração não roda', () async {
      gravarMes('2026-10', [compra('L1')]);
      await servicos.iniciar();
      expect(repo.carregar('2026-10').metodo, isNull);
    });

    test('iniciar sem correção não marca pendente', () async {
      gravarMes('2026-10', [compra('L1')]);
      await servicos.iniciar();
      expect(repo.lerConfig().pendente, isFalse);
      expect(disco.existe('config.json'), isFalse);
    });

    test('config ilegível: iniciar devolve erroConfig e salvarPreferencias '
        'lança sem tocar o arquivo', () async {
      disco.gravar('config.json', '{');
      gravarMes('2026-10', [compra('L1', ticker: 'AAPL34', tipo: 'Ação')]);
      final e = await servicos.iniciar();
      expect(
        e.erroConfig,
        'O arquivo config.json está ilegível; nada foi alterado.',
      );
      expect(eventos.whereType<EventoConfigIlegivel>(), isNotEmpty);
      await espera(
        servicos.salvarPreferencias(
          const Preferencias(tema: TemaVisual.terminal),
        ),
        'O arquivo config.json está ilegível; nada foi alterado.',
      );
      expect(disco.ler('config.json'), '{');
    });

    test('preferências vão para extras e preservam o resto', () async {
      final cfg = Config(
        radar: [ItemRadar(ticker: 'VALE3', desde: '2026-10-01', mod: 5)],
        metas: [
          Meta.fromJson({...baseMeta, 'mod': 7}),
        ],
      );
      repo.gravarConfig(cfg, carimbar: false);
      final antes = repo.lerConfig();
      await servicos.salvarPreferencias(
        const Preferencias(
          tema: TemaVisual.terminal,
          notificarNoticias: false,
          ordemRadar: 'alta',
        ),
      );
      final depois = repo.lerConfig();
      expect(depois.extras['tema_visual'], 'terminal');
      expect(depois.extras['noticias_notificar'], false);
      expect(depois.extras['radar_ordem_lista'], 'alta');
      expect(depois.tema, 'Dark');
      expect(depois.radar.single.toJson(), antes.radar.single.toJson());
      expect(depois.metas.single.toJson(), antes.metas.single.toJson());
      expect(depois.radar.single.mod, 5);
      expect(depois.metas.single.mod, 7);

      final e = await servicos.iniciar();
      expect(e.preferencias.tema, TemaVisual.terminal);
      expect(e.preferencias.notificarNoticias, isFalse);
      expect(e.preferencias.ordemRadar, 'alta');
      expect(await agendamentos(), 0);
    });
  });

  group('config ilegível por conteúdo', () {
    const msg = 'O arquivo config.json está ilegível; nada foi alterado.';

    for (final texto in ['[]', 'null', '123']) {
      test('raiz que não é objeto ($texto) recusa gravação', () async {
        disco.gravar('config.json', texto);
        expect((await servicos.iniciar()).erroConfig, msg);
        await espera(
          servicos.salvarPreferencias(
            const Preferencias(tema: TemaVisual.terminal),
          ),
          msg,
        );
        await espera(servicos.alterarSaldo(ModoSaldo.definir, 10), msg);
        expect(disco.ler('config.json'), texto);
      });
    }

    test(
      'leitura do config que lança FormatException: iniciar abre com o aviso',
      () async {
        final repoFalho = Repositorio(_ArmazenamentoQueFalha());
        final s = ServicosLocais(
          repo: repoFalho,
          yahoo: yahooSemRede(),
          conta: ContaFalsa(),
          abrirUrl: (_) async {},
        );
        final e = await s.iniciar();
        expect(e.erroConfig, msg);
        await s.encerrar();
      },
    );

    test('campo inválido: iniciar abre com o aviso e nada é gravado', () async {
      const texto = '{"metas": [{"id": "m", "qtd": 1.5}]}';
      disco.gravar('config.json', texto);
      gravarMes('2026-10', [compra('L1', ticker: 'AAPL34', tipo: 'Ação')]);
      final e = await servicos.iniciar();
      expect(e.erroConfig, msg);
      expect(e.mesInicial, '2026-10');
      await espera(servicos.salvarPreferencias(const Preferencias()), msg);
      expect(disco.ler('config.json'), texto);
    });
  });

  group('compra', () {
    test('registrarCompra grava com tipo do ticker, id novo, agenda sync e '
        'emite EventoDadosMudaram', () async {
      final v = await servicos.registrarCompra(
        '2026-10',
        const NovaCompra(
          ticker: ' aapl34 ',
          dataCompra: '2026-10-20',
          qtd: 10,
          preco: 150.5,
        ),
      );
      final l = repo.carregar('2026-10').lotes.single;
      expect(l.id, 'id0001');
      expect(l.ticker, 'AAPL34');
      expect(l.tipo, 'BDR');
      expect(l.qtd, 10);
      expect(l.preco, 150.5);
      expect(l.dataCompra, '2026-10-20');
      expect(l.mod, ambiente.agora());
      expect(v.dados.lotes.single.id, 'id0001');
      expect(v.editavel, isTrue);
      expect(await agendamentos(), 1);
      await Future<void>.delayed(Duration.zero);
      expect(eventos.whereType<EventoDadosMudaram>(), hasLength(1));
    });

    test('registrarCompra valida ticker, data, quantidade e preço', () async {
      Future<VisaoMes> com({
        String ticker = 'PETR4',
        String data = '2026-10-20',
        int qtd = 1,
        double preco = 1,
      }) => servicos.registrarCompra(
        '2026-10',
        NovaCompra(ticker: ticker, dataCompra: data, qtd: qtd, preco: preco),
      );
      await espera(com(ticker: '  '), 'Informe o ticker.');
      await espera(com(data: ''), 'Selecione a data da compra.');
      await espera(
        com(data: '2026-10-29'),
        'A data da compra não pode ser futura.',
      );
      await espera(com(qtd: 0), 'Quantidade inválida.');
      await espera(com(preco: 0), 'Preço inválido.');
      expect(disco.existe('2026-10.json'), isFalse);
      expect(await agendamentos(), 0);
    });

    test('editarCompra usa erroEdicaoLote', () async {
      gravarMes('2026-10', [
        compra(
          'L1',
          vendas: [Venda(id: 'V1', data: '2026-10-10', qtd: 40, preco: 11)],
        ),
      ]);
      final antes = disco.ler('2026-10.json');
      await espera(
        servicos.editarCompra(
          '2026-10',
          'L1',
          const NovaCompra(
            ticker: 'PETR4',
            dataCompra: '2026-10-05',
            qtd: 30,
            preco: 10,
          ),
        ),
        'A quantidade não pode ser menor que a já vendida (40).',
      );
      await espera(
        servicos.editarCompra(
          '2026-10',
          'L1',
          const NovaCompra(
            ticker: 'PETR4',
            dataCompra: '2026-10-15',
            qtd: 100,
            preco: 10,
          ),
        ),
        'A data da compra não pode ser depois da primeira venda (10/10/2026).',
      );
      expect(disco.ler('2026-10.json'), antes);

      final v = await servicos.editarCompra(
        '2026-10',
        'L1',
        const NovaCompra(
          ticker: 'vale3',
          dataCompra: '2026-10-06',
          qtd: 60,
          preco: 12,
        ),
      );
      final l = v.dados.lotes.single;
      expect(
        (l.ticker, l.tipo, l.dataCompra, l.qtd, l.preco),
        ('VALE3', 'Ação', '2026-10-06', 60, 12.0),
      );
      expect(l.vendas, hasLength(1));
      expect(await agendamentos(), 1);
    });

    test(
      'excluirCompra remove a compra e as vendas; id inexistente recusa',
      () async {
        gravarMes('2026-10', [compra('L1'), compra('L2', ticker: 'VALE3')]);
        final v = await servicos.excluirCompra('2026-10', 'L1');
        expect(v.dados.lotes.map((l) => l.id), ['L2']);
        expect(repo.carregar('2026-10').excluidos.keys, contains('L1'));
        await espera(
          servicos.excluirCompra('2026-10', 'L1'),
          'Compra não encontrada.',
        );
        expect(await agendamentos(), 1);
      },
    );
  });

  group('venda', () {
    test('registrarVenda depois de uma mesclagem que reduziu o restante → '
        'ErroValidacao e nada gravado', () async {
      gravarMes('2026-10', [compra('L1')]);
      // outro aparelho vendeu 80 e a sincronização mesclou no disco
      final d = repo.carregar('2026-10');
      d.lotes.single.vendas.add(
        Venda(id: 'VX', data: '2026-10-10', qtd: 80, preco: 11),
      );
      repo.salvar(d);
      final antes = disco.ler('2026-10.json');
      await espera(
        servicos.registrarVenda(
          '2026-10',
          const NovaVenda(loteId: 'L1', data: '2026-10-12', qtd: 50, preco: 11),
        ),
        'Quantidade maior que a disponível (20).',
      );
      expect(disco.ler('2026-10.json'), antes);
      expect(await agendamentos(), 0);
    });

    test('registrarVenda no mês grava a venda e valida os campos', () async {
      gravarMes('2026-10', [compra('L1')]);
      Future<VendaRegistrada> vender({
        String lote = 'L1',
        String data = '2026-10-12',
        int qtd = 10,
        double preco = 11,
      }) => servicos.registrarVenda(
        '2026-10',
        NovaVenda(loteId: lote, data: data, qtd: qtd, preco: preco),
      );
      await espera(
        vender(lote: 'X'),
        'Escolha o ticker e a compra que foi vendida.',
      );
      await espera(vender(data: ''), 'Selecione a data da venda.');
      await espera(
        vender(data: '2026-10-04'),
        'Data da venda inválida para essa compra.',
      );
      await espera(
        vender(data: '2026-10-29'),
        'Data da venda inválida para essa compra.',
      );
      await espera(
        vender(data: '2026-11-01'),
        'Data da venda inválida para essa compra.',
      );
      await espera(vender(qtd: 0), 'Quantidade inválida.');
      await espera(vender(preco: 0), 'Preço inválido.');
      expect(repo.carregar('2026-10').lotes.single.vendas, isEmpty);

      final r = await vender();
      expect(r.mesGravado, isNull);
      expect(r.aviso, isNull);
      final v = repo.carregar('2026-10').lotes.single.vendas.single;
      expect(
        (v.id, v.data, v.qtd, v.preco),
        ('id0001', '2026-10-12', 10, 11.0),
      );
      expect(r.visao.apuracao.ops, hasLength(1));
      expect(await agendamentos(), 1);
    });

    test('venda retroativa com config.json ilegível não grava', () async {
      gravarMes('2026-10', [
        compra('L1', data: '2026-09-01', qtd: 100, origem: 'O1'),
      ]);
      disco.gravar('config.json', '{ruim');
      final antes = disco.listar().map((n) => (n, disco.ler(n))).toList();
      await espera(
        servicos.registrarVenda(
          '2026-10',
          const NovaVenda(
            loteId: 'L1',
            data: '2026-09-15',
            qtd: 100,
            preco: 12,
          ),
        ),
        'O arquivo config.json está ilegível; nada foi alterado.',
      );
      expect(disco.listar().map((n) => (n, disco.ler(n))).toList(), antes);
    });

    test(
      'venda retroativa grava no mês da venda e devolve o aviso do Python',
      () async {
        // darf >= 10, mês cuja DARF vence neste mês
        gravarMes('2026-10', [
          compra(
            'L1',
            ticker: 'AAPL34',
            tipo: 'BDR',
            data: '2026-09-01',
            qtd: 1000,
            origem: 'O1',
          ),
        ]);
        var r = await servicos.registrarVenda(
          '2026-10',
          const NovaVenda(
            loteId: 'L1',
            data: '2026-09-15',
            qtd: 1000,
            preco: 12,
          ),
        );
        expect(r.mesGravado, '2026-09');
        expect(
          r.aviso,
          'A venda foi gravada em 09/2026, que ficou fechado com a apuração '
          'própria. A quantidade vendida saiu da compra em 10/2026.\n\n'
          'DARF de 09/2026: R\$ 299,01 (código 6015, vence no último dia útil '
          'de 10/2026).',
        );
        expect(repo.carregar('2026-09').fechado, isTrue);
        expect(repo.carregar('2026-10').lotes, isEmpty);
        expect(r.visao.mes, '2026-10');
        expect(await agendamentos(), 1);

        // DARF vencida
        gravarMes('2026-10', [
          compra(
            'L2',
            ticker: 'AAPL34',
            tipo: 'BDR',
            data: '2026-08-01',
            qtd: 1000,
          ),
        ]);
        r = await servicos.registrarVenda(
          '2026-10',
          const NovaVenda(
            loteId: 'L2',
            data: '2026-08-20',
            qtd: 1000,
            preco: 12,
          ),
        );
        expect(
          r.aviso,
          endsWith(
            'DARF de 08/2026: R\$ 299,01 (código 6015, já vencida: pague '
            'com multa e juros).',
          ),
        );

        // 0 < DARF < 10
        gravarMes('2026-10', [
          compra('L3', ticker: 'AAPL34', tipo: 'BDR', data: '2026-07-01'),
        ]);
        r = await servicos.registrarVenda(
          '2026-10',
          const NovaVenda(
            loteId: 'L3',
            data: '2026-07-15',
            qtd: 100,
            preco: 10.5,
          ),
        );
        expect(
          r.aviso,
          endsWith(
            'A DARF de R\$ 7,41 é menor que R\$ 10 e foi somada a '
            '10/2026.',
          ),
        );

        // DARF zero
        gravarMes('2026-10', [
          compra('L4', ticker: 'AAPL34', tipo: 'BDR', data: '2026-06-01'),
        ]);
        r = await servicos.registrarVenda(
          '2026-10',
          const NovaVenda(
            loteId: 'L4',
            data: '2026-06-15',
            qtd: 100,
            preco: 10,
          ),
        );
        expect(r.aviso, endsWith('Não há DARF a pagar por essa venda.'));
      },
    );

    test(
      'venda retroativa com venda no mês atual → mensagem do Python',
      () async {
        gravarMes('2026-10', [
          compra(
            'L1',
            data: '2026-09-01',
            vendas: [Venda(id: 'V1', data: '2026-10-10', qtd: 10, preco: 11)],
          ),
        ]);
        final antes = disco.ler('2026-10.json');
        await espera(
          servicos.registrarVenda(
            '2026-10',
            const NovaVenda(
              loteId: 'L1',
              data: '2026-09-15',
              qtd: 10,
              preco: 11,
            ),
          ),
          'Essa compra já tem venda neste mês. Para registrar uma venda de mês '
          'anterior, exclua a venda deste mês, registre a antiga e depois '
          'registre de novo a deste mês.',
        );
        expect(disco.ler('2026-10.json'), antes);
        expect(disco.existe('2026-09.json'), isFalse);
      },
    );

    test(
      'quantidade acima da livre em metas → mensagem com a quantidade livre',
      () async {
        gravarMes('2026-10', [compra('L1', data: '2026-09-01')]);
        repo.gravarConfig(
          Config(
            metas: [
              Meta.fromJson({...baseMeta, 'qtd': 70, 'status': 'ativa'}),
            ],
          ),
        );
        final antes = disco.ler('2026-10.json');
        await espera(
          servicos.registrarVenda(
            '2026-10',
            const NovaVenda(
              loteId: 'L1',
              data: '2026-09-15',
              qtd: 50,
              preco: 11,
            ),
          ),
          'Há metas de venda ativas nessa compra. Quantidade livre: 30. '
          'Cancele ou ajuste a meta antes.',
        );
        expect(await servicos.reservadoEmMetas('L1'), 70);
        expect(disco.ler('2026-10.json'), antes);
        expect(disco.existe('2026-09.json'), isFalse);
      },
    );

    test('editarVenda valida contra a compra sem a própria venda', () async {
      gravarMes('2026-10', [
        compra(
          'L1',
          vendas: [
            Venda(id: 'V1', data: '2026-10-10', qtd: 60, preco: 11),
            Venda(id: 'V2', data: '2026-10-11', qtd: 30, preco: 11),
          ],
        ),
      ]);
      Future<VisaoMes> editar(String data, int qtd) => servicos.editarVenda(
        '2026-10',
        'V1',
        NovaVenda(loteId: 'L1', data: data, qtd: qtd, preco: 12),
      );
      await espera(
        editar('2026-10-10', 71),
        'Quantidade maior que a disponível (70).',
      );
      await espera(
        editar('2026-10-04', 60),
        'Data da venda inválida para essa compra.',
      );
      await espera(
        editar('2026-09-30', 60),
        'Data da venda inválida para essa compra.',
      );
      final v = await editar('2026-10-12', 70);
      final venda = v.dados.lotes.single.vendas.first;
      expect(
        (venda.id, venda.data, venda.qtd, venda.preco),
        ('V1', '2026-10-12', 70, 12.0),
      );
      await espera(
        servicos.editarVenda(
          '2026-10',
          'XX',
          const NovaVenda(loteId: 'L1', data: '2026-10-12', qtd: 1, preco: 1),
        ),
        'Venda não encontrada.',
      );
      expect(await agendamentos(), 1);
    });

    test('excluirVenda remove a venda', () async {
      gravarMes('2026-10', [
        compra(
          'L1',
          vendas: [Venda(id: 'V1', data: '2026-10-10', qtd: 60, preco: 11)],
        ),
      ]);
      final v = await servicos.excluirVenda('2026-10', 'V1');
      expect(v.dados.lotes.single.vendas, isEmpty);
      expect(repo.carregar('2026-10').excluidos.keys, contains('V1'));
      await espera(
        servicos.excluirVenda('2026-10', 'V1'),
        'Venda não encontrada.',
      );
    });
  });

  group('venda em várias compras', () {
    NovaVendaQtd venda(int qtd, {String grupo = 'g'}) => NovaVendaQtd(
      ticker: 'PETR4',
      data: '2026-10-20',
      qtd: qtd,
      preco: 15,
      grupo: grupo,
    );

    setUp(() {
      gravarMes('2026-10', [
        compra('A', data: '2026-10-01', preco: 12),
        compra('B', data: '2026-10-02', preco: 10),
      ]);
    });

    Future<int> mudancas() async {
      await Future<void>.delayed(Duration.zero);
      return eventos.whereType<EventoDadosMudaram>().length;
    }

    test('novoGrupoVenda usa o gerador de ids', () async {
      expect(await servicos.novoGrupoVenda(), 'id0001');
    });

    test('comprasElegiveis e previaVenda', () async {
      final el = await servicos.comprasElegiveis(
        '2026-10',
        'PETR4',
        '2026-10-20',
      );
      expect(el.map((l) => l.id), ['A', 'B']);
      final p = await servicos.previaVenda('2026-10', venda(150));
      expect(p.linhas.map((l) => l.item.qtd), [100, 50]);
      expect(
        repo.carregar('2026-10').lotes.every((l) => l.vendas.isEmpty),
        isTrue,
      );
    });

    test(
      'previaVenda de um grupo existente libera a quantidade dele',
      () async {
        await servicos.registrarVendaQtd('2026-10', venda(200));
        // sem liberar, 200 de 200 já vendidas: não haveria saldo para a prévia
        final p = await servicos.previaVenda('2026-10', venda(200));
        expect(p.linhas.map((l) => l.item.qtd), [100, 100]);
        final outra = venda(10, grupo: 'h');
        await expectLater(
          servicos.previaVenda('2026-10', outra),
          throwsA(isA<ErroValidacao>()),
        );
      },
    );

    test('registrarVendaQtd devolve a visão e dispara um evento', () async {
      final r = await servicos.registrarVendaQtd('2026-10', venda(150));
      expect(r.aviso, isNull);
      final ids = [
        for (final l in r.visao.dados.lotes)
          for (final v in l.vendas) v.id,
      ];
      expect(ids, ['g.2', 'g.1']);
      expect(await mudancas(), 1);
      expect(await agendamentos(), 1);
    });

    test('registrarVendaQtd duplicada avisa e não grava', () async {
      await servicos.registrarVendaQtd('2026-10', venda(150));
      final depois = disco.ler('2026-10.json');
      final r = await servicos.registrarVendaQtd('2026-10', venda(150));
      expect(r.aviso, 'Essa venda já foi registrada.');
      expect(disco.ler('2026-10.json'), depois);
      expect(await mudancas(), 1);
    });

    test('editarGrupoVenda troca as linhas do grupo', () async {
      await servicos.registrarVendaQtd('2026-10', venda(150));
      final v = await servicos.editarGrupoVenda('2026-10', 'g', venda(50));
      final ids = [
        for (final l in v.dados.lotes)
          for (final x in l.vendas) x.id,
      ];
      expect(ids, ['g']);
      expect(await mudancas(), 2);
    });

    test('previaVenda avisa de metas ativas sem bloquear', () async {
      repo.gravarConfig(
        Config(
          metas: [
            Meta(
              id: 'm1',
              ticker: 'PETR4',
              tipo: 'Ação',
              gatilho: 'stop',
              loteId: 'B',
              qtd: 60,
              criadaEm: '2026-10-10',
            ),
          ],
        ),
      );
      expect((await servicos.previaVenda('2026-10', venda(40))).aviso, isNull);
      final p = await servicos.previaVenda('2026-10', venda(150));
      expect(p.aviso, contains('metas ativas em PETR4, compra de 02/10/2026'));
      expect(p.aviso, contains('meta stop de 60'));
    });

    test('previaVenda não falha com config.json ilegível', () async {
      disco.gravar('config.json', '{ruim');
      final p = await servicos.previaVenda('2026-10', venda(150));
      expect(p.aviso, isNull);
      expect(p.linhas, isNotEmpty);
    });

    test('editarVenda recusa linha de grupo com várias compras', () async {
      await servicos.registrarVendaQtd('2026-10', venda(150));
      await espera(
        servicos.editarVenda(
          '2026-10',
          'g.1',
          const NovaVenda(loteId: 'B', data: '2026-10-20', qtd: 10, preco: 15),
        ),
        'Essa venda foi dividida em várias compras. Edite a venda inteira, '
        'não uma linha só.',
      );
    });

    test('excluir uma linha do grupo apaga o grupo inteiro', () async {
      await servicos.registrarVendaQtd('2026-10', venda(150));
      final v = await servicos.excluirVenda('2026-10', 'g.1');
      expect(v.dados.lotes.every((l) => l.vendas.isEmpty), isTrue);
      expect(
        repo.carregar('2026-10').excluidos.keys,
        containsAll(['g.1', 'g.2']),
      );
    });

    test('excluir venda simples não apaga outro grupo', () async {
      await servicos.registrarVendaQtd('2026-10', venda(20, grupo: 'x'));
      await servicos.registrarVendaQtd('2026-10', venda(30, grupo: 'x2'));
      await servicos.excluirVenda('2026-10', 'x');
      final ids = [
        for (final l in repo.carregar('2026-10').lotes)
          for (final v in l.vendas) v.id,
      ];
      expect(ids, ['x2']);
    });
  });

  group('mês', () {
    test('mês fechado recusa mutação', () async {
      gravarMes('2026-09', [compra('L1', data: '2026-09-01')], fechado: true);
      final antes = disco.ler('2026-09.json');
      const c = NovaCompra(
        ticker: 'PETR4',
        dataCompra: '2026-09-10',
        qtd: 1,
        preco: 1,
      );
      const v = NovaVenda(loteId: 'L1', data: '2026-09-10', qtd: 1, preco: 1);
      await espera(
        servicos.registrarCompra('2026-09', c),
        'O mês está fechado.',
      );
      await espera(
        servicos.editarCompra('2026-09', 'L1', c),
        'O mês está fechado.',
      );
      await espera(
        servicos.excluirCompra('2026-09', 'L1'),
        'O mês está fechado.',
      );
      await espera(
        servicos.registrarVenda('2026-09', v),
        'O mês está fechado.',
      );
      await espera(
        servicos.editarVenda('2026-09', 'V', v),
        'O mês está fechado.',
      );
      await espera(
        servicos.excluirVenda('2026-09', 'V'),
        'O mês está fechado.',
      );
      await espera(servicos.fecharMes('2026-09'), 'O mês está fechado.');
      expect(disco.ler('2026-09.json'), antes);
      expect(await agendamentos(), 0);
      final visao = await servicos.carregarMes('2026-09');
      expect(visao.editavel, isFalse);
    });

    test('mês corrompido vira ErroValidacao com o nome do mês', () async {
      disco.gravar(
        '2026-09.json',
        '{"mes": "2026-09", "fechado": false, "darf_anterior": 0, "lotes": '
            '[{"id": "L1", "ticker": "PETR4", "tipo": "Ação", '
            '"data_compra": "2026-09-01", "qtd": 1.5, "preco": 10, '
            '"vendas": [], "mod": 0}], "excluidos": {}, "mod": 0}',
      );
      gravarMes('2026-10', [compra('L1')]);
      final v = await servicos.carregarMes('2026-09');
      expect(v.erroLeitura, startsWith('Não foi possível ler o mês 09/2026'));
      expect(v.dados.lotes, isEmpty);
      expect(v.editavel, isFalse);
      expect((await servicos.carregarMes('2026-10')).erroLeitura, isNull);
      await espera(
        servicos.registrarCompra(
          '2026-09',
          const NovaCompra(
            ticker: 'VALE3',
            dataCompra: '2026-09-10',
            qtd: 1,
            preco: 1,
          ),
        ),
        v.erroLeitura!,
      );
      // o seletor de mês continua funcionando
      expect(await servicos.mesesComDados(), ['2026-09', '2026-10']);
      expect(await servicos.mesInicial(), '2026-09');
    });

    test(
      'mesesSemVendaRetroativa = meses anteriores que não aceitam',
      () async {
        gravarMes('2026-07', [compra('A', data: '2026-07-01')], fechado: true);
        gravarMes('2026-08', [], fechado: true);
        gravarMes('2026-09', [compra('B', data: '2026-09-01')]);
        gravarMes('2026-10', [compra('C')]);
        expect(await servicos.mesesSemVendaRetroativa('2026-10'), {
          '2026-07',
          '2026-09',
        });
      },
    );

    test('mesInicial e mesesComDados', () async {
      expect(await servicos.mesInicial(), '2026-10');
      expect(await servicos.mesesComDados(), isEmpty);
      gravarMes('2026-08', [], fechado: true);
      gravarMes('2026-09', []);
      expect(await servicos.mesInicial(), '2026-09');
      expect(await servicos.mesesComDados(), ['2026-08', '2026-09']);
    });

    test('sugestoesTicker devolve tickers e tipos', () async {
      gravarMes('2026-10', [
        compra('L1'),
        compra('L2', ticker: 'AAPL34', tipo: 'BDR'),
      ]);
      final s = await servicos.sugestoesTicker('2026-10');
      expect(s.tickers, ['AAPL34', 'PETR4']);
      expect(s.tipos, {'PETR4': 'Ação', 'AAPL34': 'BDR'});
      final c = await servicos.sugestoesTicker('2026-10', soCustodia: true);
      expect(c.tickers, ['AAPL34', 'PETR4']);
    });

    test('fecharMes devolve mensagemFechamento e agenda sync', () async {
      gravarMes('2026-10', [compra('L1', qtd: 10)]);
      final f = await servicos.fecharMes('2026-10');
      expect(f.mensagem, startsWith('Não há DARF a pagar neste mês.'));
      expect(
        f.mensagem,
        endsWith('Ativos não vendidos foram levados para 11/2026.'),
      );
      expect(f.visao.dados.fechado, isTrue);
      expect(repo.carregar('2026-11').lotes.single.origem, 'L1');
      expect(await agendamentos(), 1);
    });

    test('fecharMes com o mês seguinte ilegível não grava nada', () async {
      gravarMes('2026-10', [compra('L1', qtd: 10)]);
      disco.gravar('2026-11.json', '{');
      final antes = disco.ler('2026-10.json');
      await expectLater(
        servicos.fecharMes('2026-10'),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            startsWith('Não foi possível ler o mês 11/2026'),
          ),
        ),
      );
      expect(disco.ler('2026-10.json'), antes);
      expect(await agendamentos(), 0);
    });

    test(
      'venda retroativa para mês de destino corrompido cita o mês',
      () async {
        gravarMes('2026-10', [compra('L1', data: '2026-09-01')]);
        disco.gravar('2026-09.json', '{');
        final antes = disco.ler('2026-10.json');
        await expectLater(
          servicos.registrarVenda(
            '2026-10',
            const NovaVenda(
              loteId: 'L1',
              data: '2026-09-15',
              qtd: 10,
              preco: 11,
            ),
          ),
          throwsA(
            isA<ErroValidacao>().having(
              (e) => e.mensagem,
              'mensagem',
              startsWith('Não foi possível ler o mês 09/2026'),
            ),
          ),
        );
        expect(disco.ler('2026-10.json'), antes);
      },
    );

    test('amigo: meses e mês inicial vêm dos dados carregados', () async {
      gravarMes('2026-10', [compra('L1')]);
      servicos.usarAmigo(
        'ana@x.com',
        DadosPlanilha(
          meses: {
            '2026-08': Mes(mes: '2026-08', fechado: true),
            '2026-09': Mes(
              mes: '2026-09',
              lotes: [compra('A1', data: '2026-09-02')],
            ),
          },
          amigos: [],
          radar: [],
          excluidos: {},
          caixa: null,
        ),
      );
      expect(await servicos.mesesComDados(amigo: 'ana@x.com'), [
        '2026-08',
        '2026-09',
      ]);
      expect(await servicos.mesInicial(amigo: 'ana@x.com'), '2026-09');
      final v = await servicos.carregarMes('2026-09', amigo: 'ana@x.com');
      expect(v.somenteLeitura, isTrue);
      expect(v.editavel, isFalse);
      expect(v.dados.lotes.single.id, 'A1');
      final vazio = await servicos.carregarMes('2026-05', amigo: 'ana@x.com');
      expect(vazio.dados.lotes, isEmpty);
      await espera(
        servicos.carregarMes('2026-09', amigo: 'outro@x.com'),
        'Os dados de outro@x.com não estão carregados.',
      );
    });
  });

  group('posições', () {
    void gravarCadeia() {
      gravarMes('2026-02', [
        compra(
          'A',
          data: '2026-02-10',
          vendas: [Venda(id: 'V1', data: '2026-02-20', qtd: 30, preco: 11)],
        ),
      ], fechado: true);
      gravarMes('2026-04', [
        compra('A2', origem: 'A', data: '2026-02-10', qtd: 70),
      ]);
    }

    test('mês sem arquivo: devolve a posição do último dia e não cria o '
        'arquivo', () async {
      gravarCadeia();
      final v = await servicos.posicoes('2026-03');
      expect(v.dataCorte, '2026-03-31');
      expect(v.corrente, isFalse);
      final p = v.posicoes.single;
      expect((p.ticker, p.qtd), ('PETR4', 70));
      expect(disco.existe('2026-03.json'), isFalse);
      expect(repo.listarMeses(), ['2026-02', '2026-04']);
    });

    test('mês de hoje: o corte é hoje', () async {
      gravarCadeia();
      final v = await servicos.posicoes('2026-10');
      expect((v.dataCorte, v.corrente), ('2026-10-28', true));
      expect(v.posicoes.single.qtd, 70);
      expect(await agendamentos(), 0);
    });
  });

  group('caixa', () {
    test('caixa e alterarSaldo', () async {
      gravarMes('2026-10', [compra('L1', data: '2026-10-05')]);
      var c = await servicos.caixa();
      expect(c.resumo.definido, isFalse);
      expect(c.hoje, '2026-10-28');
      expect(c.amigo, isNull);

      c = await servicos.alterarSaldo(ModoSaldo.definir, 5000);
      expect(c.resumo.definido, isTrue);
      expect(repo.lerConfig().caixa.saldo, 5000);
      expect(repo.lerConfig().caixa.data, '2026-10-28');
      final disponivel = c.resumo.disponivel;
      expect(await agendamentos(), 1);

      c = await servicos.alterarSaldo(ModoSaldo.aporte, 250.5);
      expect(c.resumo.disponivel, closeTo(disponivel + 250.5, 1e-9));
      c = await servicos.alterarSaldo(ModoSaldo.retirada, 100);
      expect(c.resumo.disponivel, closeTo(disponivel + 150.5, 1e-9));
      expect(await agendamentos(), 3);

      await espera(
        servicos.alterarSaldo(ModoSaldo.aporte, 0),
        'Informe um valor maior que zero.',
      );
      await espera(
        servicos.alterarSaldo(ModoSaldo.retirada, -5),
        'Informe um valor maior que zero.',
      );
      await espera(
        servicos.alterarSaldo(ModoSaldo.definir, double.nan),
        'Informe um valor válido.',
      );
      expect(await agendamentos(), 3);

      c = await servicos.alterarSaldo(ModoSaldo.definir, 0);
      expect(c.resumo.disponivel, 0);
    });

    test('alterarSaldo com config ilegível não grava', () async {
      disco.gravar('config.json', '{');
      await espera(
        servicos.alterarSaldo(ModoSaldo.definir, 10),
        'O arquivo config.json está ilegível; nada foi alterado.',
      );
      expect(disco.ler('config.json'), '{');
    });

    test('caixa do amigo usa o caixa e os meses da planilha dele', () async {
      gravarMes('2026-10', [compra('L1')]);
      repo.gravarConfig(Config(caixa: Caixa(saldo: 1, data: '2026-10-01')));
      servicos.usarAmigo(
        'ana@x.com',
        DadosPlanilha(
          meses: {},
          amigos: [],
          radar: [],
          excluidos: {},
          caixa: Caixa(saldo: 777, data: '2026-10-20'),
        ),
      );
      final c = await servicos.caixa(amigo: 'ana@x.com');
      expect(c.amigo, 'ana@x.com');
      expect(c.resumo.saldoBase, 777);
      expect(c.resumo.itens, isEmpty);
      servicos.limparAmigo();
      await espera(
        servicos.caixa(amigo: 'ana@x.com'),
        'Os dados de ana@x.com não estão carregados.',
      );
    });
  });

  group('custo médio', () {
    /// 09/2026 fechado pelo custo médio com a compra L1 de 100 a 10,00 (posição
    /// final 1000,30); 10/2026 aberto com a cópia dela.
    void gravarCorte({bool marcarOutubro = true}) {
      repo.salvar(
        Mes(
          mes: '2026-09',
          fechado: true,
          metodo: metodoCustoMedio,
          lotes: [compra('L1', data: '2026-09-01')],
        ),
      );
      final out = Mes(
        mes: '2026-10',
        lotes: [compra('C1', origem: 'L1', data: '2026-09-01')],
      );
      if (marcarOutubro) marcarCustoMedio(out);
      repo.salvar(out);
    }

    test('mês aberto posterior ao corte é marcado ao carregar', () async {
      gravarCorte(marcarOutubro: false);
      final antesDeMarcar = disco.ler('2026-10.json')!;
      ambiente = Ambiente.fixo(agora: 1790000000.5);
      final v = await servicos.carregarMes('2026-10');
      expect(v.dados.metodo, metodoCustoMedio);
      expect(v.apuracao.metodo, metodoCustoMedio);
      final gravado = repo.carregar('2026-10');
      expect(gravado.metodo, metodoCustoMedio);
      // herdada de 09: arredondar(100 × 10 × 1,0003) = 1000,30
      expect(gravado.posicaoInicial!['PETR4']!.qtd, 100);
      expect(gravado.posicaoInicial!['PETR4']!.custo, closeTo(1000.30, 1e-9));
      expect(await agendamentos(), 1);
      // marcar ao carregar não carimba: o mês fechado em outro aparelho
      // continua vencendo a mesclagem pelo mod
      expect(
        gravado.mod,
        Mes.fromJson(jsonPythonDecode(antesDeMarcar)! as Map<String, Object?>)
            .mod,
      );
      // já marcado: carregar de novo não grava
      final antes = disco.ler('2026-10.json');
      await servicos.carregarMes('2026-10');
      expect(disco.ler('2026-10.json'), antes);
    });

    test(
      'mês seguinte a mês fechado marcado herda posição e prejuízo ao carregar',
      () async {
        // 09: 100 a R$ 1.050,00 e prejuízo day trade de 2; venda de 40 a
        // 9,00 baixa arredondar(40 × 1050 / 100) = 420 → 630,00 (60);
        // resultado 360 − 420 − 360 × 0,0003 = −60,108 (prejuízo comum)
        repo.salvar(
          Mes(
            mes: '2026-09',
            fechado: true,
            metodo: metodoCustoMedio,
            posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1050)},
            prejuizoAnterior: PrejuizoAcumulado(dayTrade: 2),
            lotes: [
              compra(
                'C0',
                origem: 'L0',
                data: '2026-08-01',
                vendas: [
                  Venda(id: 'V1', data: '2026-09-15', qtd: 40, preco: 9),
                ],
              ),
            ],
          ),
        );
        // gravado por um aparelho 1.12, sem o marcador
        gravarMes('2026-10', [
          compra('C0~2026-10', origem: 'C0', data: '2026-08-01', qtd: 60),
        ]);
        final v = await servicos.carregarMes('2026-10');
        expect(v.apuracao.inconsistentes, isEmpty);
        final out = repo.carregar('2026-10');
        expect(out.metodo, metodoCustoMedio);
        expect(out.posicaoInicial!['PETR4']!.qtd, 60);
        expect(out.posicaoInicial!['PETR4']!.custo, closeTo(630.00, 1e-9));
        expect(out.prejuizoAnterior!.comum, closeTo(60.108, 1e-9));
        expect(out.prejuizoAnterior!.dayTrade, 2.0);
      },
    );

    test('primeira mutação de mês sem marcador grava uma vez', () async {
      gravarCorte(marcarOutubro: false);
      final v = await servicos.registrarCompra(
        '2026-10',
        const NovaCompra(
          ticker: 'VALE3',
          dataCompra: '2026-10-02',
          qtd: 10,
          preco: 50,
        ),
      );
      expect(v.dados.metodo, metodoCustoMedio);
      expect(repo.carregar('2026-10').metodo, metodoCustoMedio);
      expect(await agendamentos(), 1);
    });

    test('cópia levada não é excluída nem trocada de ativo', () async {
      gravarCorte();
      final antes = disco.ler('2026-10.json');
      await espera(
        servicos.excluirCompra('2026-10', 'C1'),
        'Esta compra veio do mês anterior e entra no custo médio; ela não '
        'pode ser excluída. Para tirar ações da posição, registre uma venda.',
      );
      await espera(
        servicos.editarCompra(
          '2026-10',
          'C1',
          const NovaCompra(
            ticker: 'VALE3',
            dataCompra: '2026-09-01',
            qtd: 100,
            preco: 10,
          ),
        ),
        'Esta compra veio do mês anterior e entra no custo médio; ela não '
        'pode ser trocada de ativo.',
      );
      expect(disco.ler('2026-10.json'), antes);
    });

    test('sem mês de corte nada é marcado nem gravado', () async {
      gravarMes('2026-10', [compra('L1')]);
      final antes = disco.ler('2026-10.json');
      final v = await servicos.carregarMes('2026-10');
      expect(v.dados.metodo, isNull);
      expect(disco.ler('2026-10.json'), antes);
      expect(await agendamentos(), 0);
    });

    test('mês sem arquivo depois do corte é marcado só em memória', () async {
      gravarCorte();
      final v = await servicos.carregarMes('2026-12');
      expect(v.dados.metodo, metodoCustoMedio);
      expect(repo.existeMes('2026-12'), isFalse);
    });

    test('dados de amigo são marcados só em memória', () async {
      final setembro = Mes(
        mes: '2026-09',
        lotes: [compra('C1', origem: 'L1', data: '2026-08-01')],
      );
      servicos.usarAmigo(
        'ana@x.com',
        DadosPlanilha(
          meses: {
            '2026-08': Mes(
              mes: '2026-08',
              fechado: true,
              metodo: metodoCustoMedio,
            ),
            '2026-09': setembro,
          },
          amigos: [],
          radar: [],
          excluidos: {},
          caixa: null,
        ),
      );
      final v = await servicos.carregarMes('2026-09', amigo: 'ana@x.com');
      expect(v.apuracao.metodo, metodoCustoMedio);
      expect(setembro.metodo, isNull);
      expect(repo.listarMeses(), isEmpty);
    });

    test('compra com data anterior ao mês é recusada', () async {
      gravarCorte();
      final antes = disco.ler('2026-10.json');
      await espera(
        servicos.registrarCompra(
          '2026-10',
          const NovaCompra(
            ticker: 'VALE3',
            dataCompra: '2026-09-30',
            qtd: 10,
            preco: 50,
          ),
        ),
        'Em meses pelo custo médio, a compra precisa ter data dentro do mês, '
        'a partir de 01/10/2026.',
      );
      expect(disco.ler('2026-10.json'), antes);
      final v = await servicos.registrarCompra(
        '2026-10',
        const NovaCompra(
          ticker: 'VALE3',
          dataCompra: '2026-10-01',
          qtd: 10,
          preco: 50,
        ),
      );
      expect(v.dados.lotes, hasLength(2));
      expect(v.apuracao.inconsistentes, isEmpty);
    });

    test('cópia levada não edita qtd nem preço', () async {
      gravarCorte();
      await espera(
        servicos.editarCompra(
          '2026-10',
          'C1',
          const NovaCompra(
            ticker: 'PETR4',
            dataCompra: '2026-09-01',
            qtd: 120,
            preco: 10,
          ),
        ),
        'Compra levada de um mês anterior: quantidade e preço fazem parte da '
        'posição inicial e não podem ser editados.',
      );
    });

    test('retroativa a partir do corte é recusada', () async {
      gravarCorte();
      final antes = disco.ler('2026-10.json');
      await espera(
        servicos.registrarVenda(
          '2026-10',
          const NovaVenda(loteId: 'C1', data: '2026-09-15', qtd: 10, preco: 11),
        ),
        'Meses apurados por custo médio não aceitam venda retroativa.',
      );
      expect(disco.ler('2026-10.json'), antes);
      expect(await servicos.mesesSemVendaRetroativa('2026-10'), {'2026-09'});
    });

    test('inconsistência bloqueia o fechamento', () async {
      gravarCorte();
      final out = repo.carregar('2026-10');
      out.posicaoInicial = {'PETR4': PosicaoFiscal(qtd: 80, custo: 800)};
      repo.salvar(out);
      final antes = disco.ler('2026-10.json');
      final v = await servicos.carregarMes('2026-10');
      expect(v.apuracao.inconsistentes, ['PETR4']);
      await espera(
        servicos.fecharMes('2026-10'),
        'O mês não pode ser fechado com saldo inconsistente.\n\n'
        'Saldo inconsistente em PETR4: confira as vendas',
      );
      expect(disco.ler('2026-10.json'), antes);
      expect(repo.existeMes('2026-11'), isFalse);
    });
  });
}

const baseMeta = <String, Object?>{
  'id': 'meta-a',
  'ticker': 'PETR4',
  'tipo': 'Ação',
  'lote_id': 'L1',
  'qtd': 100,
  'preco_alvo': 20.0,
  'criada_em': '2026-10-20T11:00:00-03:00',
};
