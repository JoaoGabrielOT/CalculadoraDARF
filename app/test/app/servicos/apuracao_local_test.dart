import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_locais.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/conta_falsa.dart';

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
