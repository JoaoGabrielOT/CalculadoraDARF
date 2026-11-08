import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/servicos_locais.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integracoes/apoio/cliente_falso.dart';
import '../apoio/conta_falsa.dart';
import '../apoio/yahoo_falso.dart';

const _msgConfig = 'O arquivo config.json está ilegível; nada foi alterado.';

late ArmazenamentoMemoria disco;
late Repositorio repo;
late ServicosLocais servicos;
late ClienteFalso falso;
late List<EventoServico> eventos;

/// Código HTTP por ticker (padrão 200) e preço da meta do chart.
late Map<String, int> status;
late Map<String, String> precos;

/// Chamado em cada pedido, antes da resposta (a "busca" que demora).
void Function(PedidoGravado)? aoPedir;

const _metaBase = <String, Object?>{
  'id': 'meta-a',
  'ticker': 'PETR4',
  'tipo': 'Ação',
  'lote_id': 'L1',
  'qtd': 100,
  'preco_alvo': 20.0,
  'criada_em': '2026-10-20T11:00:00-03:00',
  'status': 'ativa',
};

Lote compra(
  String id, {
  String ticker = 'PETR4',
  String data = '2026-10-05',
  int qtd = 100,
  double preco = 10,
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: preco,
);

void gravarMes(List<Lote> lotes) =>
    repo.salvar(Mes(mes: '2026-10', lotes: lotes));

void gravarMeta([Map<String, Object?> extra = const {}]) {
  final cfg = repo.lerConfig();
  cfg.metas.add(Meta.fromJson({..._metaBase, ...extra}));
  repo.gravarConfig(cfg, carimbar: false);
}

Future<void> espera(Future<Object?> f, String mensagem) => expectLater(
  f,
  throwsA(isA<ErroValidacao>().having((e) => e.mensagem, 'mensagem', mensagem)),
);

Future<int> agendamentos() async {
  await Future<void>.delayed(Duration.zero);
  return eventos
      .whereType<EventoConta>()
      .where((e) => e.conta.status == StatusSync.pendente)
      .length;
}

RespostaFalsa _responder(PedidoGravado p) {
  aoPedir?.call(p);
  final t = p.url.pathSegments.last.replaceAll('.SA', '');
  final st = status[t] ?? 200;
  if (st != 200) return RespostaFalsa(st, texto: 'erro', motivo: 'erro');
  return RespostaFalsa(200, texto: corpoChart(preco: precos[t] ?? '10.5'));
}

void main() {
  setUp(() {
    ambiente = Ambiente.fixo();
    disco = ArmazenamentoMemoria();
    repo = Repositorio(disco);
    status = {};
    precos = {};
    aoPedir = null;
    falso = ClienteFalso(_responder);
    servicos = ServicosLocais(
      repo: repo,
      yahoo: yahooFalso(falso),
      conta: ContaFalsa(email: 'ana@gmail.com'),
      abrirUrl: (_) async {},
      atrasoAgendamento: const Duration(hours: 1),
    );
    eventos = [];
    servicos.eventos.listen(eventos.add);
  });

  tearDown(() async {
    encerrarVerificacao();
    await servicos.encerrar();
    ambiente = Ambiente.sistema();
  });

  group('verificação de metas', () {
    test('sem metas ativas → SemMetasAtivas', () async {
      expect(await servicos.verificarMetas(), isA<SemMetasAtivas>());
    });

    test('trava ocupada → VerificacaoEmAndamento', () async {
      gravarMes([compra('L1')]);
      gravarMeta();
      expect(tentarIniciarVerificacao(), isTrue);
      expect(await servicos.verificarMetas(), isA<VerificacaoEmAndamento>());
    });

    test('sucesso → VerificacaoConcluida com o relatório', () async {
      gravarMes([compra('L1')]);
      gravarMeta();
      status['PETR4'] = 404;
      final r = await servicos.verificarMetas();
      expect(r, isA<VerificacaoConcluida>());
      final rel = (r as VerificacaoConcluida).relatorio;
      expect(rel.erros.single.id, 'meta-a');
      expect(verificacaoEmAndamento, isFalse);
    });

    test('falha na aplicação → VerificacaoFalhou, trava liberada e nunca '
        '"em andamento" (bug §9)', () async {
      gravarMes([compra('L1')]);
      gravarMeta();
      status['PETR4'] = 404;
      aoPedir = (_) => disco.gravar('config.json', '{');
      final r = await servicos.verificarMetas();
      expect(r, isA<VerificacaoFalhou>());
      expect((r as VerificacaoFalhou).mensagem, contains(_msgConfig));
      expect(verificacaoEmAndamento, isFalse);
      // a segunda tentativa falha de novo pelo mesmo motivo, não por trava
      expect(await servicos.verificarMetas(), isA<VerificacaoFalhou>());
      expect(disco.ler('config.json'), '{');
    });

    test('alteração da config durante a busca do histórico sobrevive à '
        'aplicação', () async {
      gravarMes([compra('L1')]);
      gravarMeta();
      status['PETR4'] = 404;
      var feito = false;
      aoPedir = (_) {
        if (feito) return;
        feito = true;
        final cfg = repo.lerConfig();
        adicionarRadar(cfg, 'XPTO3');
        repo.gravarConfig(cfg);
      };
      await servicos.verificarMetas();
      final cfg = repo.lerConfig();
      expect(cfg.radar.map((r) => r.ticker), ['XPTO3']);
      expect(cfg.excluidos.containsKey('radar:XPTO3'), isFalse);
      expect(cfg.metas.single.ultimoErro, isNotNull);
    });

    test(
      'prepararFechamento: alteração da config durante a busca sobrevive',
      () async {
        gravarMes([compra('L1')]);
        gravarMeta();
        status['PETR4'] = 404;
        var feito = false;
        aoPedir = (_) {
          if (feito) return;
          feito = true;
          final cfg = repo.lerConfig();
          adicionarRadar(cfg, 'XPTO3');
          repo.gravarConfig(cfg);
        };
        final preparo = await servicos.prepararFechamento('2026-10');
        expect(preparo.bloqueio, isNotNull);
        final cfg = repo.lerConfig();
        expect(cfg.radar.map((r) => r.ticker), ['XPTO3']);
        expect(cfg.excluidos.containsKey('radar:XPTO3'), isFalse);
      },
    );

    test('verificação automática que mudou algo emite EventoMetas e '
        'EventoDadosMudaram e agenda sync', () async {
      gravarMes([compra('L1')]);
      gravarMeta();
      status['PETR4'] = 404;
      await servicos.verificacaoAutomatica();
      expect(await agendamentos(), 1);
      expect(eventos.whereType<EventoMetas>(), hasLength(1));
      expect(eventos.whereType<EventoDadosMudaram>(), hasLength(1));
    });

    test('verificação automática sem mudança não emite nada', () async {
      await servicos.verificacaoAutomatica();
      expect(await agendamentos(), 0);
      expect(eventos.whereType<EventoMetas>(), isEmpty);
      expect(eventos.whereType<EventoDadosMudaram>(), isEmpty);
    });
  });

  group('radar', () {
    test('adicionarRadar: tira .SA, valida o formato e o repetido', () async {
      final item = await servicos.adicionarRadar(' petr4.sa ');
      expect(item.ticker, 'PETR4');
      expect(repo.lerConfig().radar.single.ticker, 'PETR4');
      expect(await agendamentos(), 1);
      expect(eventos.whereType<EventoDadosMudaram>(), hasLength(1));
      await espera(servicos.adicionarRadar('AB'), 'Ticker inválido.');
      await espera(servicos.adicionarRadar('ABCDEFGH'), 'Ticker inválido.');
      await espera(servicos.adicionarRadar('PE-R4'), 'Ticker inválido.');
      await espera(servicos.adicionarRadar('PETR4'), 'PETR4 já está no radar.');
      expect(repo.lerConfig().radar, hasLength(1));
    });

    test('importarRadar só adiciona os que faltam e devolve quantos', () async {
      await servicos.adicionarRadar('PETR4');
      final n = await servicos.importarRadar([
        ItemRadar(ticker: 'PETR4', desde: '2026-10-01'),
        ItemRadar(ticker: 'VALE3', nome: 'Vale', desde: '2026-10-01'),
        ItemRadar(ticker: 'VALE3', nome: 'Vale', desde: '2026-10-01'),
        ItemRadar(ticker: 'ITUB4', desde: '2026-10-01'),
      ]);
      expect(n, 2);
      final radar = repo.lerConfig().radar;
      expect(radar.map((r) => r.ticker), ['PETR4', 'VALE3', 'ITUB4']);
      expect(radar[1].nome, 'Vale');
      expect(await servicos.importarRadar([radar[0]]), 0);
    });

    test('reordenarRadar grava pos e agenda sync', () async {
      for (final t in ['PETR4', 'VALE3', 'ITUB4']) {
        await servicos.adicionarRadar(t);
      }
      await servicos.reordenarRadar(['ITUB4', 'PETR4', 'VALE3']);
      final radar = repo.lerConfig().radar;
      expect(radar.map((r) => r.ticker), ['ITUB4', 'PETR4', 'VALE3']);
      expect(radar.map((r) => r.pos), [0, 1, 2]);
      expect(await agendamentos(), 4);
    });

    test('removerRadar carimba exclusão e agenda sync', () async {
      await servicos.adicionarRadar('PETR4');
      await servicos.removerRadar('PETR4');
      final cfg = repo.lerConfig();
      expect(cfg.radar, isEmpty);
      expect(cfg.excluidos.containsKey('radar:PETR4'), isTrue);
      expect(await agendamentos(), 2);
    });

    test('radar devolve a ordem do usuário, a custódia e os meus', () async {
      gravarMes([compra('L1', ticker: 'VALE3')]);
      await servicos.adicionarRadar('PETR4');
      await servicos.adicionarRadar('VALE3');
      await servicos.reordenarRadar(['VALE3', 'PETR4']);
      final v = await servicos.radar();
      expect(v.itens.map((r) => r.ticker), ['VALE3', 'PETR4']);
      expect(v.custodia, {'VALE3'});
      expect(v.meus, {'PETR4', 'VALE3'});
      expect(v.amigo, isNull);
    });

    test('radar(amigo:) devolve o radar do amigo ordenado, custódia vazia e '
        'meus = o meu radar', () async {
      gravarMes([compra('L1', ticker: 'VALE3')]);
      await servicos.adicionarRadar('PETR4');
      servicos.usarAmigo(
        'bia@gmail.com',
        DadosPlanilha(
          meses: {},
          amigos: [],
          radar: [
            ItemRadar(ticker: 'ITUB4', desde: '2026-10-01', pos: 1),
            ItemRadar(ticker: 'VALE3', desde: '2026-10-01', pos: 0),
          ],
          excluidos: {},
          caixa: null,
        ),
      );
      final v = await servicos.radar(amigo: 'bia@gmail.com');
      expect(v.itens.map((r) => r.ticker), ['VALE3', 'ITUB4']);
      expect(v.custodia, isEmpty);
      expect(v.meus, {'PETR4'});
      expect(v.amigo, 'bia@gmail.com');
      await espera(
        servicos.radar(amigo: 'outro@x.com'),
        'Os dados de outro@x.com não estão carregados.',
      );
    });
  });

  group('cotações', () {
    test(
      'nome vindo do Yahoo preenche o item sem nome e agenda sync',
      () async {
        await servicos.adicionarRadar('PETR4');
        final c = await servicos.cotacao('PETR4');
        expect(c, isA<CotacaoOk>());
        expect((c as CotacaoOk).dados.preco, 10.5);
        expect(repo.lerConfig().radar.single.nome, 'Petrobras');
        expect(await agendamentos(), 2);
      },
    );

    test('nome já preenchido não é trocado nem agenda sync', () async {
      await servicos.adicionarRadar('PETR4');
      final cfg = repo.lerConfig()..radar.single.nome = 'Meu nome';
      repo.gravarConfig(cfg);
      await servicos.cotacao('PETR4', nome: 'Meu nome');
      expect(repo.lerConfig().radar.single.nome, 'Meu nome');
      expect(await agendamentos(), 1);
    });

    test('ativo fora do radar não grava nada', () async {
      final c = await servicos.cotacao('VALE3');
      expect(c, isA<CotacaoOk>());
      expect(disco.existe('config.json'), isFalse);
    });

    test('erro vira CotacaoErro com mensagemErro', () async {
      status['PETR4'] = 404;
      status['VALE3'] = 429;
      final a = await servicos.cotacao('PETR4');
      expect(a, isA<CotacaoErro>());
      expect((a as CotacaoErro).ticker, 'PETR4');
      expect(a.mensagem, 'Sem dados para PETR4 no Yahoo Finance.');
      final b = await servicos.cotacao('VALE3') as CotacaoErro;
      expect(
        b.mensagem,
        'Limite de consultas do Yahoo atingido. Tente em alguns minutos.',
      );
    });

    test('config ilegível: a cotação chega e o arquivo fica intacto', () async {
      disco.gravar('config.json', '{');
      final c = await servicos.cotacao('PETR4');
      expect(c, isA<CotacaoOk>());
      expect(disco.ler('config.json'), '{');
    });

    test('limparCacheCotacoes força nova consulta', () async {
      await servicos.cotacao('PETR4');
      await servicos.cotacao('PETR4');
      expect(falso.pedidos, hasLength(1));
      await servicos.limparCacheCotacoes();
      await servicos.cotacao('PETR4');
      expect(falso.pedidos, hasLength(2));
    });

    test('precoVenda de hoje usa a cotação atual', () async {
      expect(await servicos.precoVenda('PETR4', '2026-10-28'), (
        10.5,
        'Cotação atual',
      ));
    });

    test(
      'precosCarteira: preço, null se falhou, ausente se nunca tentou',
      () async {
        status['VALE3'] = 500;
        final p = await servicos.precosCarteira({'PETR4', 'VALE3'});
        expect(p, {'PETR4': 10.5, 'VALE3': null});
      },
    );

    test(
      'precosCarteira: atualização em curso deixa os pendentes ausentes',
      () async {
        final primeira = servicos.precosCarteira({'PETR4', 'VALE3'});
        final segunda = await servicos.precosCarteira({'PETR4', 'VALE3'});
        expect(segunda, isEmpty);
        expect(await primeira, {'PETR4': 10.5, 'VALE3': 10.5});
      },
    );

    test('cotacoesAtuais: preço, fonte e hora de Brasília; falha vira nulo '
        'sem derrubar os outros', () async {
      status['VALE3'] = 500;
      final c = await servicos.cotacoesAtuais({'PETR4', 'VALE3'});
      expect(c['VALE3'], isNull);
      final p = c['PETR4']!;
      expect((p.preco, p.fonte), (10.5, 'Yahoo'));
      expect(p.hora.desvio, fusoBrasilia);
      expect(p.hora.timestamp, closeTo(1761000000.123, 0.001));
    });

    test('cotacoesAtuais: 429 depois de um preço mantém o preço e a hora '
        'antiga', () async {
      final primeira = (await servicos.cotacoesAtuais({'PETR4'}))['PETR4']!;
      ambiente = Ambiente.fixo(agora: 1761000000.123 + 120);
      status['PETR4'] = 429;
      final c = (await servicos.cotacoesAtuais({'PETR4'}))['PETR4']!;
      expect(c.preco, 10.5);
      expect(c.hora, primeira.hora);
      expect(falso.pedidos, hasLength(2));
    });

    test('cotacoesAtuais: ticker que nunca teve preço vem nulo', () async {
      status['VALE3'] = 429;
      expect((await servicos.cotacoesAtuais({'VALE3'}))['VALE3'], isNull);
    });

    test('429 depois de um preço mantém o preço', () async {
      expect(await servicos.precosCarteira({'PETR4'}), {'PETR4': 10.5});
      ambiente = Ambiente.fixo(agora: 1761000000.123 + 120);
      status['PETR4'] = 429;
      expect(await servicos.precosCarteira({'PETR4'}), {'PETR4': 10.5});
      expect(falso.pedidos, hasLength(2));
    });
  });

  group('metas', () {
    test('metas lista da mais nova para a mais antiga com descrições e '
        'lotes livres', () async {
      gravarMes([compra('L1'), compra('L2', ticker: 'VALE3')]);
      gravarMeta();
      gravarMeta({
        'id': 'meta-b',
        'lote_id': 'L2',
        'ticker': 'VALE3',
        'qtd': 40,
        'criada_em': '2026-10-25T11:00:00-03:00',
      });
      gravarMeta({
        'id': 'meta-c',
        'status': 'cancelada',
        'criada_em': '2026-10-26T11:00:00-03:00',
      });
      final v = await servicos.metas();
      expect(v.metas.map((m) => m.id), ['meta-c', 'meta-b', 'meta-a']);
      expect(v.descricoes.keys, {'meta-a', 'meta-b', 'meta-c'});
      expect(v.ativas, 2);
      expect({for (final l in v.lotes) l.lote.id: l.livre}, {'L2': 60});
    });

    test('sugestoesMetas monta um item por posição com qtd = livre ou '
        'restante e o rodapé', () async {
      gravarMes([compra('L1'), compra('L2', ticker: 'VALE3')]);
      gravarMeta({'qtd': 40});
      gravarMeta({'id': 'meta-b', 'lote_id': 'L2', 'ticker': 'VALE3'});
      final v = await servicos.sugestoesMetas();
      expect(v.itens.map((s) => s.posicao.lote.id), ['L1', 'L2']);
      // L1 tem 60 livres; L2 está toda reservada e usa o restante
      expect(v.itens.map((s) => s.qtd), [60, 100]);
      expect(v.itens.map((s) => s.item.qtd), [60, 100]);
      expect(v.rodape.first.$1, 'Patrimônio considerado');
      expect(falso.pedidos.map((p) => p.url.pathSegments.last).toSet(), {
        'PETR4.SA',
        'VALE3.SA',
      });
    });

    test('sugestoesMetas: falha na consulta vira erro do item', () async {
      gravarMes([compra('L1')]);
      status['PETR4'] = 404;
      final v = await servicos.sugestoesMetas();
      expect(v.itens.single.item.erro, isNotNull);
    });

    test('sugestoesMetas sem compras em aberto devolve vazio', () async {
      final v = await servicos.sugestoesMetas();
      expect(v.itens, isEmpty);
    });

    test('calcularPrecoAlvo e projetarPreco usam a compra do mês', () async {
      gravarMes([compra('L1')]);
      final alvo = await servicos.calcularPrecoAlvo('L1', 100, 100);
      expect(alvo.preco, greaterThan(10));
      final proj = await servicos.projetarPreco('L1', 100, 12);
      expect(proj.lucroAposImposto, isNot(alvo.lucroAposImposto));
      await espera(
        servicos.calcularPrecoAlvo('NAO', 100, 100),
        'Essa compra não existe mais.',
      );
      await espera(
        servicos.projetarPreco('NAO', 100, 12),
        'Essa compra não existe mais.',
      );
    });

    test('compra de hoje é day trade no preço-alvo e na projeção', () async {
      gravarMes([compra('L1', data: '2026-10-28')]);
      final alvo = await servicos.calcularPrecoAlvo('L1', 100, 100);
      expect(alvo.dayTrade, isTrue);
      expect((await servicos.projetarPreco('L1', 100, 12)).dt, isTrue);
    });

    test(
      'criarStop e criarMetaAlvo com OCO; parceiraOco e cancelarMeta',
      () async {
        gravarMes([compra('L1')]);
        final stop = await servicos.criarStop('L1', 100, 9);
        expect(stop.gatilho, 'stop');
        expect((await servicos.parceiraOco('L1', 'alvo'))?.id, stop.id);
        final alvo = await servicos.criarMetaAlvo(
          'L1',
          100,
          20,
          lucroDesejado: 500,
          ocoCom: stop.id,
        );
        final metas = repo.lerConfig().metas;
        expect(metas, hasLength(2));
        expect(metas[0].oco, isNotNull);
        expect(metas[0].oco, metas[1].oco);
        expect(alvo.lucroDesejado, 500);
        expect(await servicos.parceiraOco('L1', 'alvo'), isNull);
        expect(await agendamentos(), 2);
        await servicos.cancelarMeta(alvo.id);
        expect(
          repo.lerConfig().metas.firstWhere((m) => m.id == alvo.id).status,
          'cancelada',
        );
        await espera(
          servicos.cancelarMeta(alvo.id),
          'Só metas ativas podem ser canceladas.',
        );
      },
    );

    test(
      'erros do núcleo chegam como ErroValidacao e nada é gravado',
      () async {
        gravarMes([compra('L1')]);
        await expectLater(
          servicos.criarMetaAlvo('L1', 500, 20),
          throwsA(isA<ErroValidacao>()),
        );
        await expectLater(
          servicos.criarStop('L1', 100, 9, precoAtual: 8),
          throwsA(isA<ErroValidacao>()),
        );
        expect(repo.lerConfig().metas, isEmpty);
      },
    );
  });

  group('config ilegível: nenhum escritor toca o arquivo', () {
    const textos = <String, String>{
      'JSON inválido': '{',
      'raiz que não é objeto': '[1]',
      'campo com valor inválido': '{"metas": [{"id": "m", "qtd": 1.5}]}',
    };
    for (final MapEntry(key: nome, value: texto) in textos.entries) {
      test('$nome: escritores de radar e metas lançam o erro da guarda e o '
          'arquivo fica byte a byte igual', () async {
        gravarMes([compra('L1')]);
        disco.gravar('config.json', texto);
        await espera(servicos.adicionarRadar('PETR4'), _msgConfig);
        await espera(
          servicos.importarRadar([ItemRadar(ticker: 'VALE3', desde: 'x')]),
          _msgConfig,
        );
        await espera(servicos.reordenarRadar(['PETR4']), _msgConfig);
        await espera(servicos.removerRadar('PETR4'), _msgConfig);
        await espera(servicos.criarStop('L1', 100, 9), _msgConfig);
        await espera(servicos.criarMetaAlvo('L1', 100, 20), _msgConfig);
        await espera(servicos.cancelarMeta('meta-a'), _msgConfig);
        await espera(servicos.metas(), _msgConfig);
        await espera(servicos.sugestoesMetas(), _msgConfig);
        await espera(servicos.prepararFechamento('2026-10'), _msgConfig);
        final r = await servicos.verificarMetas();
        expect(r, isA<VerificacaoFalhou>());
        expect((r as VerificacaoFalhou).mensagem, _msgConfig);
        expect(disco.ler('config.json'), texto);
        expect(falso.pedidos, isEmpty);
      });
    }
  });
}
