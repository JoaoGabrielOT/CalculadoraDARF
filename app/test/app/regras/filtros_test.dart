import 'package:calculadoradarf/app/regras/filtros.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

Lote lote(
  String id,
  String ticker,
  String data,
  int qtd,
  double preco, {
  String tipo = 'Ação',
  int vendido = 0,
}) => Lote(
  id: id,
  ticker: ticker,
  tipo: tipo,
  dataCompra: data,
  qtd: qtd,
  preco: preco,
  vendas: [
    if (vendido > 0) Venda(id: 'V$id', data: data, qtd: vendido, preco: 1),
  ],
);

// Cadastro: A, B, C, D, E.
final lotes = [
  lote('A', 'VALE3', '2026-03-05', 100, 60), // aberto, total 6000
  lote('B', 'AAPL34', '2026-03-02', 10, 50, tipo: 'BDR'), // aberto, total 500
  lote('C', 'PETR4', '2026-03-09', 200, 30, vendido: 200), // vendido, 6000
  lote('D', 'PETR4', '2026-03-01', 50, 40, vendido: 20), // restante 30, 2000
  lote('E', 'BBAS3', '2026-03-05', 100, 25), // aberto, total 2500
];

const precos = {'VALE3': 66.0, 'AAPL34': 45.0, 'PETR4': 35.0};
double? cotacao(String t) => precos[t];

List<String> ids(FiltroLotes f) => [
  for (final l in filtrarLotes(lotes, f, cotacao)) l.id,
];

Operacao op(
  String id,
  String ticker,
  String data,
  int qtd,
  double preco, {
  required bool dt,
  String tipo = 'Ação',
  required double bruto,
  required double liquido,
  required double imposto,
  required double taxas,
  double corretagem = 0,
}) {
  final o = Operacao(
    c: ResultadoVenda(
      dt: dt,
      compra: 0,
      venda: 0,
      taxas: taxas,
      corretagem: corretagem,
      bruto: bruto,
      liquido: liquido,
    ),
    ticker: ticker,
    tipo: tipo,
    data: data,
    qtd: qtd,
    preco: preco,
    loteId: 'L$id',
    vendaId: id,
  );
  o.regime = dt ? 'Day trade' : (tipo == 'Ação' ? 'Swing (isento)' : 'Swing');
  o.imposto = imposto;
  return o;
}

// Entrada: a, b, c, d, e.
final ops = [
  op(
    'a',
    'PETR4',
    '2026-03-10',
    100,
    35,
    dt: false,
    bruto: 500,
    liquido: 480,
    imposto: 0,
    taxas: 5,
  ),
  op(
    'b',
    'AAPL34',
    '2026-03-12',
    10,
    60,
    tipo: 'BDR',
    dt: false,
    bruto: 100,
    liquido: 90,
    imposto: 15,
    taxas: 2,
  ),
  op(
    'c',
    'VALE3',
    '2026-03-12',
    50,
    70,
    dt: true,
    bruto: 300,
    liquido: 250,
    imposto: 40,
    taxas: 3,
    corretagem: 2,
  ),
  op(
    'd',
    'PETR4',
    '2026-03-03',
    20,
    31,
    dt: false,
    bruto: 20,
    liquido: 15,
    imposto: 0,
    taxas: 1,
  ),
  op(
    'e',
    'BBAS3',
    '2026-03-20',
    100,
    28,
    dt: false,
    bruto: 500,
    liquido: 480,
    imposto: 15,
    taxas: 5,
  ),
];

List<String> idsV(FiltroVendas f) => [
  for (final o in filtrarVendas(ops, f)) o.vendaId,
];

void main() {
  group('filtrarLotes (android/main.py:915-940)', () {
    test('padrão: ordem de cadastro, nada filtrado', () {
      expect(ids(FiltroLotes()), ['A', 'B', 'C', 'D', 'E']);
    });

    test('cadastro decrescente inverte a lista', () {
      expect(ids(FiltroLotes(desc: true)), ['E', 'D', 'C', 'B', 'A']);
    });

    test('situação: em aberto tem restante > 0; vendidos tem restante 0', () {
      expect(ids(FiltroLotes(situacao: 'Em aberto')), ['A', 'B', 'D', 'E']);
      expect(ids(FiltroLotes(situacao: 'Vendidos')), ['C']);
    });

    test('tipo', () {
      expect(ids(FiltroLotes(tipo: 'BDR')), ['B']);
      expect(ids(FiltroLotes(tipo: 'Ação')), ['A', 'C', 'D', 'E']);
    });

    test('busca por trecho do ticker, ignorando caixa e espaços', () {
      expect(ids(FiltroLotes(busca: 'PETR')), ['C', 'D']);
      expect(ids(FiltroLotes(busca: ' petr4 ')), ['C', 'D']);
      expect(ids(FiltroLotes(busca: 'XXXX')), isEmpty);
    });

    test('ordem por data, com desempate estável (A e E: mesma data)', () {
      expect(ids(FiltroLotes(ordem: 'data')), ['D', 'B', 'A', 'E', 'C']);
      expect(ids(FiltroLotes(ordem: 'data', desc: true)), [
        'C',
        'A',
        'E',
        'B',
        'D',
      ]);
    });

    test('ordem por ticker; empate C e D mantém o cadastro', () {
      expect(ids(FiltroLotes(ordem: 'ticker')), ['B', 'E', 'C', 'D', 'A']);
      expect(ids(FiltroLotes(ordem: 'ticker', desc: true)), [
        'A',
        'C',
        'D',
        'E',
        'B',
      ]);
    });

    test('ordem por quantidade', () {
      expect(ids(FiltroLotes(ordem: 'qtd')), ['B', 'D', 'A', 'E', 'C']);
      expect(ids(FiltroLotes(ordem: 'qtd', desc: true)), [
        'C',
        'A',
        'E',
        'D',
        'B',
      ]);
    });

    test('ordem por preço de compra', () {
      expect(ids(FiltroLotes(ordem: 'preco')), ['E', 'C', 'D', 'B', 'A']);
      expect(ids(FiltroLotes(ordem: 'preco', desc: true)), [
        'A',
        'B',
        'D',
        'C',
        'E',
      ]);
    });

    test('ordem por total, com empate A e C (6000)', () {
      expect(ids(FiltroLotes(ordem: 'total')), ['B', 'D', 'E', 'A', 'C']);
      expect(ids(FiltroLotes(ordem: 'total', desc: true)), [
        'A',
        'C',
        'E',
        'D',
        'B',
      ]);
    });

    test('ordem por restante, com empates em zero', () {
      expect(ids(FiltroLotes(ordem: 'restante')), ['C', 'B', 'D', 'A', 'E']);
      expect(ids(FiltroLotes(ordem: 'restante', desc: true)), [
        'A',
        'E',
        'D',
        'B',
        'C',
      ]);
    });

    test('ordem por preço atual: sem cotação ou sem restante vai ao início', () {
      // E sem cotação e C sem restante valem -inf (empatam, ordem do cadastro).
      expect(ids(FiltroLotes(ordem: 'atual')), ['C', 'E', 'D', 'B', 'A']);
      expect(ids(FiltroLotes(ordem: 'atual', desc: true)), [
        'A',
        'B',
        'D',
        'C',
        'E',
      ]);
    });

    test('ordem por ganho/perda: sem resultado vale -inf', () {
      // A: (66-60)*100=600; B: (45-50)*10=-50; D: (35-40)*30=-150;
      // C vendido e E sem cotação: sem resultado.
      expect(ids(FiltroLotes(ordem: 'resultado')), ['C', 'E', 'D', 'B', 'A']);
      expect(ids(FiltroLotes(ordem: 'resultado', desc: true)), [
        'A',
        'B',
        'D',
        'C',
        'E',
      ]);
    });

    test('preço zero conta como sem cotação', () {
      final f = FiltroLotes(ordem: 'atual');
      final r = filtrarLotes(lotes, f, (t) => t == 'VALE3' ? 0.0 : cotacao(t));
      expect([for (final l in r) l.id], ['A', 'C', 'E', 'D', 'B']);
    });

    test('filtros combinados e ordem desconhecida usa o cadastro', () {
      expect(
        ids(
          FiltroLotes(situacao: 'Em aberto', tipo: 'Ação', ordem: 'qualquer'),
        ),
        ['A', 'D', 'E'],
      );
    });

    test('não altera a lista de entrada', () {
      filtrarLotes(lotes, FiltroLotes(ordem: 'ticker', desc: true), cotacao);
      expect([for (final l in lotes) l.id], ['A', 'B', 'C', 'D', 'E']);
    });
  });

  group('filtrarVendas (android/main.py:942-955)', () {
    test('padrão: data decrescente, empate pela entrada', () {
      expect(idsV(FiltroVendas()), ['e', 'b', 'c', 'a', 'd']);
    });

    test('data crescente', () {
      expect(idsV(FiltroVendas(desc: false)), ['d', 'a', 'b', 'c', 'e']);
    });

    test('operação: Swing inclui "Swing (isento)"; Day trade', () {
      expect(idsV(FiltroVendas(operacao: 'Swing')), ['e', 'b', 'a', 'd']);
      expect(idsV(FiltroVendas(operacao: 'Day trade')), ['c']);
    });

    test('custo médio: "Misto" aparece em Swing e em Day trade', () {
      final misto = op(
        'm',
        'ITUB4',
        '2026-03-15',
        100,
        30,
        dt: false,
        bruto: 10,
        liquido: 9,
        imposto: 1,
        taxas: 1,
      )..regime = 'Misto';
      List<String> so(String operacao) => [
        for (final o in filtrarVendas([
          ...ops,
          misto,
        ], FiltroVendas(operacao: operacao)))
          o.vendaId,
      ];
      expect(so('Swing'), ['e', 'm', 'b', 'a', 'd']);
      expect(so('Day trade'), ['m', 'c']);
    });

    test('vendasPorRegime conta a venda mista nos dois regimes', () {
      Apuracao com(List<Operacao> ops) => Apuracao(
        ops: ops,
        vendasAcoesSt: 0,
        isento: true,
        bruto: 0,
        custos: 0,
        impSt: 0,
        impDt: 0,
        impostoTotal: 0,
        irrf: 0,
        lucroLiquido: 0,
        darfMes: 0,
        darfAnterior: 0,
        darf: 0,
      );
      // método por compra: pela marcação dt da venda
      expect(vendasPorRegime(com(ops)), (4, 1));
      Operacao fiscal(String id, int qtdDt) => op(
        id,
        'PETR4',
        '2026-03-10',
        100,
        12,
        dt: qtdDt == 100,
        bruto: 0,
        liquido: 0,
        imposto: 0,
        taxas: 0,
      )..qtdDt = qtdDt;
      // custo médio: pela quantidade day trade da linha
      expect(
        vendasPorRegime(
          com([fiscal('a', 0), fiscal('b', 40), fiscal('c', 100)]),
        ),
        (2, 2),
      );
    });

    test('tipo e busca', () {
      expect(idsV(FiltroVendas(tipo: 'BDR')), ['b']);
      expect(idsV(FiltroVendas(busca: 'petr')), ['a', 'd']);
      expect(idsV(FiltroVendas(busca: 'ZZZ')), isEmpty);
    });

    test('ordem por ticker', () {
      expect(idsV(FiltroVendas(ordem: 'ticker', desc: false)), [
        'b',
        'e',
        'a',
        'd',
        'c',
      ]);
      expect(idsV(FiltroVendas(ordem: 'ticker')), ['c', 'a', 'd', 'e', 'b']);
    });

    test('ordem por quantidade', () {
      expect(idsV(FiltroVendas(ordem: 'qtd', desc: false)), [
        'b',
        'd',
        'c',
        'a',
        'e',
      ]);
      expect(idsV(FiltroVendas(ordem: 'qtd')), ['a', 'e', 'c', 'd', 'b']);
    });

    test('ordem por preço de venda', () {
      expect(idsV(FiltroVendas(ordem: 'preco', desc: false)), [
        'e',
        'd',
        'a',
        'b',
        'c',
      ]);
      expect(idsV(FiltroVendas(ordem: 'preco')), ['c', 'b', 'a', 'd', 'e']);
    });

    test('ordem por lucro bruto, empate a e e (500)', () {
      expect(idsV(FiltroVendas(ordem: 'bruto', desc: false)), [
        'd',
        'b',
        'c',
        'a',
        'e',
      ]);
      expect(idsV(FiltroVendas(ordem: 'bruto')), ['a', 'e', 'c', 'b', 'd']);
    });

    test('ordem após taxas', () {
      expect(idsV(FiltroVendas(ordem: 'liquido', desc: false)), [
        'd',
        'b',
        'c',
        'a',
        'e',
      ]);
      expect(idsV(FiltroVendas(ordem: 'liquido')), ['a', 'e', 'c', 'b', 'd']);
    });

    test('ordem por imposto, empates em zero e em 15', () {
      expect(idsV(FiltroVendas(ordem: 'imposto', desc: false)), [
        'a',
        'd',
        'b',
        'e',
        'c',
      ]);
      expect(idsV(FiltroVendas(ordem: 'imposto')), ['c', 'b', 'e', 'a', 'd']);
    });

    test('ordem por taxas soma a corretagem', () {
      // taxas+corretagem: a 5, b 2, c 5, d 1, e 5.
      expect(idsV(FiltroVendas(ordem: 'taxas', desc: false)), [
        'd',
        'b',
        'a',
        'c',
        'e',
      ]);
      expect(idsV(FiltroVendas(ordem: 'taxas')), ['a', 'c', 'e', 'b', 'd']);
    });

    test('ordem desconhecida usa a data', () {
      expect(idsV(FiltroVendas(ordem: 'xyz')), idsV(FiltroVendas()));
    });

    test('não altera a lista de entrada', () {
      filtrarVendas(ops, FiltroVendas(ordem: 'ticker'));
      expect([for (final o in ops) o.vendaId], ['a', 'b', 'c', 'd', 'e']);
    });
  });

  group('descPadrao (android/main.py:873-874)', () {
    test('ordens que começam decrescentes', () {
      for (final o in [
        'data', 'total', 'resultado', 'atual', 'bruto', 'liquido', 'imposto',
        'taxas', //
      ]) {
        expect(descPadrao(o), isTrue, reason: o);
      }
    });

    test('as demais começam crescentes', () {
      for (final o in ['cadastro', 'ticker', 'qtd', 'preco', 'restante']) {
        expect(descPadrao(o), isFalse, reason: o);
      }
    });
  });

  group('filtrarAgenda (calculadora_darf.py:1873-1876)', () {
    final itens = [
      LancamentoCaixa(
        id: '1',
        data: '2026-03-02',
        ticker: 'A',
        tipo: 'Compra',
        qtd: 1,
        valor: -10,
        liquidacao: '2026-03-04',
      )..status = 'Liquidado',
      LancamentoCaixa(
        id: '2',
        data: '2026-03-10',
        ticker: 'B',
        tipo: 'Venda',
        qtd: 1,
        valor: 10,
        liquidacao: '2026-03-12',
      )..status = 'Pendente',
      LancamentoCaixa(
        id: '3',
        data: '2026-03-11',
        ticker: 'C',
        tipo: 'Venda',
        qtd: 1,
        valor: 10,
        liquidacao: '2026-03-13',
      )..status = 'Pendente',
    ];

    List<String> aplicar(String f) => [
      for (final i in filtrarAgenda(itens, f)) i.id,
    ];

    test('Todos, A liquidar e Liquidados', () {
      expect(aplicar('Todos'), ['1', '2', '3']);
      expect(aplicar('A liquidar'), ['2', '3']);
      expect(aplicar('Liquidados'), ['1']);
    });

    test('filtro desconhecido não esconde nada', () {
      expect(aplicar('outro'), ['1', '2', '3']);
    });
  });
}
