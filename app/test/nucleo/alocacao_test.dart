import 'package:calculadoradarf/nucleo/alocacao.dart';
import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/apuracao_medio.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

Lote _lote(
  String id,
  String data,
  int qtd,
  double preco, {
  List<Venda>? vendas,
  String ticker = 'PETR4',
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: 'Ação',
  dataCompra: data,
  qtd: qtd,
  preco: preco,
  vendas: vendas,
);

List<(String, int, bool)> _resumo(List<ItemAlocacao> l) => [
  for (final i in l) (i.lote.id, i.qtd, i.travado),
];

class _Disco extends ArmazenamentoMemoria {
  int gravacoes = 0;
  bool falhar = false;

  @override
  void gravar(String nome, String conteudo) {
    if (falhar) throw StateError('disco cheio');
    gravacoes++;
    super.gravar(nome, conteudo);
  }
}

void main() {
  final a = _lote('A', '2026-01-05', 100, 12.0);
  final b = _lote('B', '2026-01-10', 100, 10.0);
  final c = _lote('C', '2026-01-03', 100, 11.0);

  group('automático', () {
    test('automático escolhe o menor custo efetivo', () {
      final r = alocarAutomatico([a, b, c], 150, '2026-02-10');
      expect(_resumo(r), [('B', 100, false), ('C', 50, false)]);
    });

    test('desempate por data e depois por id', () {
      final b2 = _lote('B', '2026-01-10', 100, 10.0);
      final c2 = _lote('C', '2026-01-03', 100, 10.0);
      expect(_resumo(alocarAutomatico([b2, c2], 50, '2026-02-10')), [
        ('C', 50, false),
      ]);
      final x = _lote('X2', '2026-01-03', 100, 10.0);
      final y = _lote('X1', '2026-01-03', 100, 10.0);
      expect(_resumo(alocarAutomatico([x, y], 50, '2026-02-10')), [
        ('X1', 50, false),
      ]);
    });

    test('compras do dia primeiro e travadas', () {
      final d = _lote('D', '2026-02-10', 50, 13.0);
      final r = alocarAutomatico([b, d], 120, '2026-02-10');
      expect(_resumo(r), [('D', 50, true), ('B', 70, false)]);
    });

    test('compra do dia maior que a venda consome só a venda', () {
      final d = _lote('D', '2026-02-10', 50, 13.0);
      final r = alocarAutomatico([b, d], 30, '2026-02-10');
      expect(_resumo(r), [('D', 30, true)]);
    });

    test('venda parcial e várias compras', () {
      final r = alocarAutomatico([a, c], 130, '2026-02-10');
      expect(_resumo(r), [('C', 100, false), ('A', 30, false)]);
      expect(r.fold(0, (s, i) => s + i.qtd), 130);
    });

    test('quantidade zero ou negativa lança', () {
      for (final q in [0, -5]) {
        expect(
          () => alocarAutomatico([a, c], q, '2026-02-10'),
          throwsA(
            isA<ErroValidacao>().having(
              (e) => e.mensagem,
              'mensagem',
              'Quantidade inválida.',
            ),
          ),
        );
      }
    });

    test('quantidade insuficiente lança', () {
      expect(
        () => alocarAutomatico([a, c], 250, '2026-02-10'),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Quantidade indisponível: só há 200 ações de PETR4 nessa data.',
          ),
        ),
      );
    });

    test('usa só o que resta de cada compra', () {
      final p = _lote(
        'P',
        '2026-01-01',
        100,
        9.0,
        vendas: [Venda(id: 'v', data: '2026-01-08', qtd: 60, preco: 12)],
      );
      expect(_resumo(alocarAutomatico([p, a], 50, '2026-02-10')), [
        ('P', 40, false),
        ('A', 10, false),
      ]);
    });
  });

  group('elegíveis e custo', () {
    test('comprasElegiveis filtra data, ticker e restante', () {
      final cheio = _lote(
        'F',
        '2026-01-01',
        10,
        9.0,
        vendas: [Venda(id: 'v', data: '2026-01-02', qtd: 10, preco: 10)],
      );
      final futuro = _lote('G', '2026-02-20', 10, 9.0);
      final outro = _lote('H', '2026-01-01', 10, 9.0, ticker: 'VALE3');
      final d = Mes(mes: '2026-02', lotes: [a, cheio, futuro, outro]);
      expect(comprasElegiveis(d, 'PETR4', '2026-02-10').map((l) => l.id), [
        'A',
      ]);
    });

    test('custo unitário efetivo inclui taxa e corretagem', () {
      final l = _lote('A', '2026-01-05', 100, 12.0);
      expect(custoUnitarioEfetivo(l), closeTo(12.0 * (1 + taxaB3Swing), 1e-12));
      final antes = corretagemPorOrdem;
      corretagemPorOrdem = 5.0;
      addTearDown(() => corretagemPorOrdem = antes);
      expect(
        custoUnitarioEfetivo(l),
        closeTo(12.0 * (1 + taxaB3Swing) + 0.05, 1e-12),
      );
    });
  });

  group('validarManual', () {
    final d = _lote('D', '2026-02-10', 50, 13.0);
    final el = [a, b, d];
    const dv = '2026-02-10';

    test('seleção válida devolve nulo', () {
      final sel = [ItemAlocacao(d, 50), ItemAlocacao(b, 70)];
      expect(validarManual(el, sel, 120, dv), isNull);
    });

    test('soma diferente', () {
      final sel = [ItemAlocacao(d, 50), ItemAlocacao(b, 60)];
      expect(
        validarManual(el, sel, 120, dv),
        'A soma das compras escolhidas (110) é diferente da quantidade da '
        'venda (120).',
      );
    });

    test('item acima do disponível', () {
      final sel = [ItemAlocacao(d, 50), ItemAlocacao(b, 101)];
      expect(
        validarManual(el, sel, 151, dv),
        'A compra de 10/01/2026 tem só 100 ações disponíveis.',
      );
    });

    test('compra do dia sem a quantidade obrigatória', () {
      final sel = [ItemAlocacao(a, 100), ItemAlocacao(b, 20)];
      expect(
        validarManual(el, sel, 120, dv),
        'As compras de hoje entram primeiro (day trade, regra da Receita).',
      );
    });

    test('lote fora das elegíveis', () {
      final x = _lote('X', '2026-01-01', 100, 9.0);
      expect(
        validarManual(el, [ItemAlocacao(x, 10)], 10, dv),
        'Compra fora das disponíveis nessa data.',
      );
    });

    test('manual não contorna day trade mesmo com a soma certa', () {
      final sel = [ItemAlocacao(b, 30), ItemAlocacao(d, 20)];
      expect(
        validarManual(el, sel, 50, dv),
        'As compras de hoje entram primeiro (day trade, regra da Receita).',
      );
    });

    test('item com quantidade zero não passa', () {
      final sel = [ItemAlocacao(b, 100), ItemAlocacao(a, 0)];
      expect(
        validarManual(el, sel, 100, dv),
        'Quantidade inválida em uma das compras escolhidas.',
      );
    });

    test('quantidade negativa não passa', () {
      final sel = [
        ItemAlocacao(b, 110),
        ItemAlocacao(a, -10),
        ItemAlocacao(d, 50),
      ];
      expect(validarManual(el, sel, 150, dv), isNotNull);
    });
  });

  group('montarVendas e grupo', () {
    test('um item mantém o id simples', () {
      final v = montarVendas([ItemAlocacao(a, 10)], 'g', '2026-02-10', 15, 3);
      expect(v.map((e) => e.id), ['g']);
      expect(v.single.qtd, 10);
      expect(v.single.preco, 15);
      expect(v.single.mod, 3);
    });

    test('três itens recebem sufixos e o mesmo mod', () {
      final v = montarVendas(
        [ItemAlocacao(a, 1), ItemAlocacao(b, 2), ItemAlocacao(c, 3)],
        'g',
        '2026-02-10',
        15,
        7.5,
      );
      expect(v.map((e) => e.id), ['g.1', 'g.2', 'g.3']);
      expect(v.map((e) => e.mod), [7.5, 7.5, 7.5]);
      expect(v.map((e) => e.qtd), [1, 2, 3]);
      expect(v.every((e) => e.data == '2026-02-10'), isTrue);
    });

    test('grupoDe', () {
      expect(grupoDe('g.2'), 'g');
      expect(grupoDe('auto-m1'), 'auto-m1');
      expect(grupoDe('a.b.12'), 'a.b');
      expect(grupoDe('g.x'), 'g.x');
    });
  });

  group('prévia', () {
    Mes mes() => Mes(
      mes: '2026-02',
      lotes: [
        _lote('A', '2026-02-05', 100, 12.0),
        _lote('B', '2026-02-10', 100, 10.0),
      ],
    );

    test('prévia gerencial muda com a alocação', () {
      final d = mes();
      final pa = previa(d, [ItemAlocacao(d.lotes[0], 50)], 15.0, '2026-02-20');
      final pb = previa(d, [ItemAlocacao(d.lotes[1], 50)], 15.0, '2026-02-20');
      expect(pb.gerencial, greaterThan(pa.gerencial + 1));
      final ce = custoUnitarioEfetivo(d.lotes[0]);
      expect(
        pa.linhas.single.resultadoGerencial,
        closeTo(50 * 15.0 - 50 * ce - 50 * 15.0 * taxaB3Swing, 1e-9),
      );
      expect(pa.linhas.single.custoEfetivo, closeTo(ce, 1e-12));
      expect(pa.qtdComum, 50);
      expect(pa.qtdDt, 0);
    });

    test('prévia não altera o mês e o fiscal vem da apuração', () {
      final d = mes();
      final antes = apurar(d).lucroLiquido;
      final p = previa(d, [ItemAlocacao(d.lotes[0], 50)], 15.0, '2026-02-20');
      expect(d.lotes[0].vendas, isEmpty);
      expect(apurar(d).lucroLiquido, antes);
      final copia = Mes.fromJson(d.toJson());
      copia.lotes[0].vendas.add(
        Venda(id: 'x', data: '2026-02-20', qtd: 50, preco: 15.0),
      );
      expect(p.fiscal, closeTo(apurar(copia).lucroLiquido - antes, 1e-9));
    });

    test('compra do dia conta como day trade na prévia', () {
      final d = mes();
      final p = previa(
        d,
        [
          ItemAlocacao(d.lotes[1], 40, travado: true),
          ItemAlocacao(d.lotes[0], 10),
        ],
        15.0,
        '2026-02-10',
      );
      expect(p.qtdDt, 40);
      expect(p.qtdComum, 10);
      expect(
        p.linhas.first.resultadoGerencial,
        closeTo(
          40 * 15.0 -
              40 * custoUnitarioEfetivo(d.lotes[1]) -
              40 * 15.0 * taxaB3Daytrade,
          1e-9,
        ),
      );
    });
  });

  group('prévia no custo médio', () {
    // Mês marcado: cópias A (100 @ 12) e B (100 @ 10) levadas de janeiro e a
    // compra C (50 @ 12) de 02-10. Posição inicial derivada:
    // 1.200,36 + 1.000,30 = {200, 2.200,66}.
    Mes mes() {
      final d = Mes(
        mes: '2026-02',
        lotes: [
          Lote.fromJson({
            ..._lote('A', '2026-01-05', 100, 12.0).toJson(),
            'origem': 'a',
          }),
          Lote.fromJson({
            ..._lote('B', '2026-01-10', 100, 10.0).toJson(),
            'origem': 'b',
          }),
          _lote('C', '2026-02-10', 50, 12.0),
        ],
      );
      marcarCustoMedio(d);
      return d;
    }

    test('fiscal igual para alocações diferentes da mesma venda', () {
      final d = mes();
      final pa = previa(d, [ItemAlocacao(d.lotes[0], 100)], 15.0, '2026-02-20');
      final pb = previa(d, [ItemAlocacao(d.lotes[1], 100)], 15.0, '2026-02-20');
      expect(pb.gerencial, greaterThan(pa.gerencial + 1));
      expect(pa.fiscal, closeTo(pb.fiscal, 1e-9));
      expect(pa.custoMedio, isTrue);
      // C entra em 02-10: + round(50 × 12 × 1,0003, 2) = 600,18 → {250,
      // 2.800,84}. 100 em 02-20: round(100 × 2.800,84 / 250, 2) = 1.120,34
      // baixados; 1.500 − 1.120,34 − 0,45 = 379,21 (1.500 ≤ 20.000, isento).
      expect(pa.fiscal, closeTo(379.21, 1e-9));
    });

    test('seleção manual não muda a classificação de day trade', () {
      final d = mes();
      // Venda de 60 em 02-10, dia da compra C de 50: 50 são day trade
      // qualquer que seja a compra consumida.
      final travada = [
        ItemAlocacao(d.lotes[2], 50, travado: true),
        ItemAlocacao(d.lotes[0], 10),
      ];
      final antigas = [ItemAlocacao(d.lotes[0], 60)];
      expect(
        validarManual(
          comprasElegiveis(d, 'PETR4', '2026-02-10'),
          antigas,
          60,
          '2026-02-10',
        ),
        isNotNull,
      );
      Apuracao com(List<ItemAlocacao> sel) {
        final c = Mes.fromJson(d.toJson());
        final vs = montarVendas(sel, 'g', '2026-02-10', 15.0, 0);
        for (final (k, i) in sel.indexed) {
          c.lotes.firstWhere((l) => l.id == i.lote.id).vendas.add(vs[k]);
        }
        return apurar(c);
      }

      final r1 = com(travada);
      final r2 = com(antigas);
      expect(r1.ops.fold(0, (s, o) => s + o.qtdDt!), 50);
      expect(r2.ops.fold(0, (s, o) => s + o.qtdDt!), 50);
      expect(r1.impDt, closeTo(r2.impDt, 1e-9));
      expect(r1.impSt, closeTo(r2.impSt, 1e-9));
      expect(r1.lucroLiquido, closeTo(r2.lucroLiquido, 1e-9));
      expect(
        previa(d, travada, 15.0, '2026-02-10').fiscal,
        closeTo(previa(d, antigas, 15.0, '2026-02-10').fiscal, 1e-9),
      );
    });

    test('mês sem marcador avisa que o fiscal é por compra', () {
      final d = Mes(mes: '2026-02', lotes: [_lote('A', '2026-02-05', 10, 1)]);
      expect(
        previa(d, [ItemAlocacao(d.lotes[0], 5)], 2.0, '2026-02-20').custoMedio,
        isFalse,
      );
    });
  });

  group('confirmação e edição de grupo', _confirmacao);
}

void _confirmacao() {
  late _Disco disco;
  late Repositorio repo;
  const mes = '2026-10';

  NovaVendaQtd venda(
    int qtd, {
    String grupo = 'g',
    List<(String, int)>? selecao,
    String data = '2026-10-20',
  }) => NovaVendaQtd(
    ticker: 'PETR4',
    data: data,
    qtd: qtd,
    preco: 15.0,
    grupo: grupo,
    selecao: selecao,
  );

  List<String> vendaIds() => [
    for (final l in repo.carregar(mes).lotes)
      for (final v in l.vendas) v.id,
  ];

  setUp(() {
    ambiente = Ambiente.fixo();
    disco = _Disco();
    repo = Repositorio(disco);
    repo.salvar(
      Mes(
        mes: mes,
        lotes: [
          _lote('A', '2026-10-01', 100, 12.0),
          _lote('B', '2026-10-02', 100, 10.0),
          _lote('C', '2026-10-03', 100, 11.0),
        ],
      ),
    );
    disco.gravacoes = 0;
  });

  group('confirmarVenda', () {
    test('automático grava uma vez e dá ids de grupo', () {
      final r = confirmarVenda(repo, mes, venda(150));
      expect(r.duplicada, isFalse);
      expect(disco.gravacoes, 1);
      final d = repo.carregar(mes);
      expect(vendaIds(), ['g.1', 'g.2']);
      expect(d.lotes[1].vendas.single.qtd, 100);
      expect(d.lotes[2].vendas.single.qtd, 50);
      final mods = {
        for (final l in d.lotes)
          for (final v in l.vendas) v.mod,
      };
      expect(mods, {ambiente.agora()});
    });

    test('venda de uma compra só tem id simples', () {
      confirmarVenda(repo, mes, venda(40));
      expect(vendaIds(), ['g']);
    });

    test('confirmação dupla grava uma vez', () {
      confirmarVenda(repo, mes, venda(150));
      final r = confirmarVenda(repo, mes, venda(150));
      expect(r.duplicada, isTrue);
      expect(disco.gravacoes, 1);
      expect(vendaIds(), ['g.1', 'g.2']);
    });

    test('duplicada também vale para venda simples', () {
      confirmarVenda(repo, mes, venda(40));
      expect(confirmarVenda(repo, mes, venda(40)).duplicada, isTrue);
      expect(disco.gravacoes, 1);
    });

    test('falha de gravação não deixa linhas parciais', () {
      disco.falhar = true;
      expect(() => confirmarVenda(repo, mes, venda(150)), throwsStateError);
      disco.falhar = false;
      expect(vendaIds(), isEmpty);
    });

    test('valida contra o mês recarregado', () {
      confirmarVenda(repo, mes, venda(250, grupo: 'g1'));
      expect(
        () => confirmarVenda(repo, mes, venda(100, grupo: 'g2')),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Quantidade indisponível: só há 50 ações de PETR4 nessa data.',
          ),
        ),
      );
      expect(vendaIds().where((i) => i.startsWith('g2')), isEmpty);
    });

    test('seleção manual vale e é validada', () {
      confirmarVenda(repo, mes, venda(60, selecao: [('A', 20), ('C', 40)]));
      final d = repo.carregar(mes);
      expect(d.lotes[0].vendas.single.qtd, 20);
      expect(d.lotes[2].vendas.single.qtd, 40);
      expect(vendaIds(), ['g.1', 'g.2']);
      expect(
        () => confirmarVenda(
          repo,
          mes,
          venda(10, grupo: 'h', selecao: [('A', 0), ('B', 10)]),
        ),
        throwsA(isA<ErroValidacao>()),
      );
      expect(
        () => confirmarVenda(
          repo,
          mes,
          venda(10, grupo: 'h', selecao: [('Z', 10)]),
        ),
        throwsA(isA<ErroValidacao>()),
      );
    });

    test('grupo excluído depois não ressuscita no reenvio', () {
      confirmarVenda(repo, mes, venda(150));
      final d = repo.carregar(mes);
      for (final l in d.lotes) {
        l.vendas = [];
      }
      repo.salvar(d);
      final r = confirmarVenda(repo, mes, venda(150));
      expect(r.duplicada, isTrue);
      expect(vendaIds(), isEmpty);
    });

    test('data de outro mês tem mensagem própria', () {
      expect(
        () => confirmarVenda(repo, mes, venda(10, data: '2026-09-20')),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'A venda só pode ser registrada no mês aberto (10/2026).',
          ),
        ),
      );
    });

    test('ticker é normalizado e grupo vazio é recusado', () {
      confirmarVenda(
        repo,
        mes,
        const NovaVendaQtd(
          ticker: ' petr4 ',
          data: '2026-10-20',
          qtd: 10,
          preco: 15,
          grupo: 'g',
        ),
      );
      expect(vendaIds(), ['g']);
      expect(
        () => confirmarVenda(repo, mes, venda(10, grupo: ' ')),
        throwsA(isA<ErroValidacao>()),
      );
      expect(
        () => editarGrupo(repo, mes, ' ', venda(10)),
        throwsA(isA<ErroValidacao>()),
      );
    });

    test('aviso de metas reservadas lista compra e meta, sem bloquear', () {
      final cfg = Config(
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
      );
      final d = repo.carregar(mes);
      final b = d.lotes[1];
      expect(avisoMetasReservadas(repo, cfg, d, [ItemAlocacao(b, 40)]), isNull);
      expect(
        avisoMetasReservadas(repo, cfg, d, [ItemAlocacao(b, 50)]),
        'Esta venda usa quantidade reservada por metas ativas em PETR4, '
        'compra de 02/10/2026 (meta stop de 60); a meta ficará inválida se '
        'o saldo não bastar.',
      );
      expect(
        avisoMetasReservadas(repo, cfg, d, [ItemAlocacao(d.lotes[0], 100)]),
        isNull,
      );
    });

    test('aviso: rótulo alvo, limite exato e mesma compra repetida', () {
      final cfg = Config(
        metas: [
          Meta(
            id: 'm1',
            ticker: 'PETR4',
            tipo: 'Ação',
            loteId: 'B',
            qtd: 60,
            criadaEm: '2026-10-10',
          ),
        ],
      );
      final d = repo.carregar(mes);
      final b = d.lotes[1];
      String? av(List<ItemAlocacao> l) => avisoMetasReservadas(repo, cfg, d, l);
      expect(av([ItemAlocacao(b, 40)]), isNull);
      expect(av([ItemAlocacao(b, 41)]), contains('(meta alvo de 60)'));
      expect(av([ItemAlocacao(b, 25), ItemAlocacao(b, 25)]), isNotNull);
      expect(av([ItemAlocacao(b, 20), ItemAlocacao(b, 20)]), isNull);
    });

    test('mês fechado, data futura e quantidade zero recusam', () {
      expect(
        () => confirmarVenda(repo, mes, venda(0)),
        throwsA(isA<ErroValidacao>()),
      );
      expect(
        () => confirmarVenda(repo, mes, venda(10, data: '2026-10-29')),
        throwsA(isA<ErroValidacao>()),
      );
      repo.salvar(repo.carregar(mes)..fechado = true);
      expect(
        () => confirmarVenda(repo, mes, venda(10)),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'O mês está fechado.',
          ),
        ),
      );
    });
  });

  group('editarGrupo', () {
    test('editar grupo reusa índices novos', () {
      confirmarVenda(repo, mes, venda(150));
      editarGrupo(repo, mes, 'g', venda(250));
      expect(vendaIds()..sort(), ['g.3', 'g.4', 'g.5']);
      expect(repo.carregar(mes).excluidos.keys, containsAll(['g.1', 'g.2']));
    });

    test('editar para uma compra só volta ao id simples', () {
      confirmarVenda(repo, mes, venda(150));
      editarGrupo(repo, mes, 'g', venda(50));
      expect(vendaIds(), ['g']);
      expect(repo.carregar(mes).excluidos.keys, containsAll(['g.1', 'g.2']));
    });

    test('mantém o id simples quando continua uma compra', () {
      confirmarVenda(repo, mes, venda(40));
      editarGrupo(repo, mes, 'g', venda(60));
      expect(vendaIds(), ['g']);
      expect(repo.carregar(mes).excluidos, isEmpty);
    });

    test('libera a própria quantidade do grupo ao validar', () {
      confirmarVenda(repo, mes, venda(300));
      editarGrupo(repo, mes, 'g', venda(300));
      expect(vendaIds().length, 3);
    });

    test('grupo inexistente e quantidade indisponível', () {
      confirmarVenda(repo, mes, venda(150));
      expect(
        () => editarGrupo(repo, mes, 'nada', venda(10, grupo: 'nada')),
        throwsA(isA<ErroValidacao>()),
      );
      final antes = disco.ler('$mes.json');
      expect(
        () => editarGrupo(repo, mes, 'g', venda(301)),
        throwsA(isA<ErroValidacao>()),
      );
      expect(disco.ler('$mes.json'), antes);
    });
  });
}
