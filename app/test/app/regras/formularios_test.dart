import 'package:calculadoradarf/app/regras/formularios.dart';
import 'package:calculadoradarf/app/regras/textos.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

Lote lote({
  int qtd = 100,
  String dataCompra = '2026-03-10',
  List<Venda>? vendas,
}) => Lote(
  id: 'L1',
  ticker: 'PETR4',
  tipo: 'Ação',
  dataCompra: dataCompra,
  qtd: qtd,
  preco: 30,
  vendas: vendas,
);

Venda venda(int qtd, String data) =>
    Venda(id: 'V$qtd', data: data, qtd: qtd, preco: 35);

String? erro<T>(Validacao<T> v) => switch (v) {
  Invalido(:final mensagem) => mensagem,
  Valido() => null,
};

T valor<T>(Validacao<T> v) => switch (v) {
  Valido(:final valor) => valor,
  Invalido(:final mensagem) => throw StateError('inválido: $mensagem'),
};

Validacao<NovaCompra> compra({
  String ticker = 'petr4',
  String? data = '2026-03-10',
  String qtd = '100',
  String preco = '32,50',
  String hoje = '2026-03-15',
  Lote? editando,
}) => validarCompra(
  ticker: ticker,
  data: data,
  qtd: qtd,
  preco: preco,
  hoje: hoje,
  editando: editando,
);

Validacao<NovaVenda> vender({
  Lote? lote,
  String? data = '2026-03-12',
  String qtd = '50',
  String preco = '35,00',
  String inicioMes = '2026-03-01',
  bool permitida = true,
  int reservado = 0,
  bool editando = false,
}) => validarVenda(
  lote: lote,
  data: data,
  qtd: qtd,
  preco: preco,
  inicioMes: inicioMes,
  permitida: permitida,
  reservado: reservado,
  editando: editando,
);

Apuracao apuracao({
  double darf = 0,
  double irrf = 0,
  double vendasAcoesSt = 0,
  bool isento = true,
  int vendas = 0,
}) => Apuracao(
  ops: [
    for (var i = 0; i < vendas; i++)
      Operacao(
        c: calcularVendaQtd(lote(), 1, 35, '2026-03-12'),
        ticker: 'PETR4',
        tipo: 'Ação',
        data: '2026-03-12',
        qtd: 1,
        preco: 35,
        loteId: 'L1',
        vendaId: 'V$i',
      ),
  ],
  vendasAcoesSt: vendasAcoesSt,
  isento: isento,
  bruto: 0,
  custos: 0,
  impSt: 0,
  impDt: 0,
  impostoTotal: 0,
  irrf: irrf,
  lucroLiquido: 0,
  darfMes: darf,
  darfAnterior: 0,
  darf: darf,
);

void main() {
  group('validarCompra (calculadora_darf.py:288-311)', () {
    test('compra válida: ticker em maiúsculas, quantidade e preço lidos', () {
      final c = valor(
        compra(ticker: ' petr4 ', qtd: '1.000', preco: '1.234,50'),
      );
      expect(c.ticker, 'PETR4');
      expect(c.dataCompra, '2026-03-10');
      expect(c.qtd, 1000);
      expect(c.preco, 1234.5);
    });

    test('ticker vazio', () {
      expect(erro(compra(ticker: '   ')), 'Informe o ticker.');
    });

    test('sem data', () {
      expect(erro(compra(data: null)), 'Selecione a data da compra.');
    });

    test('data futura; hoje ainda vale', () {
      expect(
        erro(compra(data: '2026-03-16')),
        'A data da compra não pode ser futura.',
      );
      expect(erro(compra(data: '2026-03-15')), isNull);
    });

    test('custo médio: data anterior ao mês e cópia levada', () {
      final mes = Mes(
        mes: '2026-03',
        metodo: metodoCustoMedio,
        posicaoInicial: {'PETR4': PosicaoFiscal(qtd: 100, custo: 1000.3)},
      );
      Validacao<NovaCompra> v(
        String data, {
        Lote? editando,
        String qtd = '100',
      }) => validarCompra(
        ticker: 'petr4',
        data: data,
        qtd: qtd,
        preco: '10,00',
        hoje: '2026-03-15',
        editando: editando,
        mes: mes,
      );
      expect(
        erro(v('2026-02-27')),
        'Em meses pelo custo médio, a compra precisa ter data dentro do mês, '
        'a partir de 01/03/2026.',
      );
      expect(erro(v('2026-03-01')), isNull);
      final copia = Lote(
        id: 'C1',
        origem: 'L1',
        ticker: 'PETR4',
        tipo: 'Ação',
        dataCompra: '2026-02-10',
        qtd: 100,
        preco: 10,
      );
      expect(
        erro(v('2026-02-10', editando: copia, qtd: '90')),
        'Compra levada de um mês anterior: quantidade e preço fazem parte da '
        'posição inicial e não podem ser editados.',
      );
      expect(erro(v('2026-02-10', editando: copia)), isNull);
    });

    test('quantidade inválida: vazia, texto, zero e fração', () {
      for (final q in ['', 'abc', '0', '1,5', '-3']) {
        expect(erro(compra(qtd: q)), 'Quantidade inválida.', reason: q);
      }
    });

    test('preço inválido: vazio, texto, zero e negativo', () {
      for (final p in ['', 'abc', '0', '-2']) {
        expect(erro(compra(preco: p)), 'Preço inválido.', reason: p);
      }
    });

    test('a ordem das checagens: ticker, data, futura, quantidade, preço', () {
      expect(
        erro(compra(ticker: '', data: null, qtd: 'x', preco: 'y')),
        'Informe o ticker.',
      );
      expect(
        erro(compra(data: null, qtd: 'x', preco: 'y')),
        'Selecione a data da compra.',
      );
      expect(
        erro(compra(data: '2027-01-01', qtd: 'x', preco: 'y')),
        'A data da compra não pode ser futura.',
      );
      expect(erro(compra(qtd: 'x', preco: 'y')), 'Quantidade inválida.');
    });

    test('edição: quantidade menor que a já vendida', () {
      final l = lote(vendas: [venda(40, '2026-03-12')]);
      expect(
        erro(compra(qtd: '30', editando: l)),
        'A quantidade não pode ser menor que a já vendida (40).',
      );
    });

    test('edição: data depois da primeira venda', () {
      final l = lote(vendas: [venda(40, '2026-03-12')]);
      expect(
        erro(compra(data: '2026-03-13', editando: l)),
        'A data da compra não pode ser depois da primeira venda (12/03/2026).',
      );
    });

    test('edição válida passa; sem edição o erro de edição não existe', () {
      final l = lote(vendas: [venda(40, '2026-03-12')]);
      expect(erro(compra(qtd: '40', data: '2026-03-12', editando: l)), isNull);
      expect(erro(compra(qtd: '1')), isNull);
    });
  });

  group('validarVenda (calculadora_darf.py:505-533)', () {
    test('venda válida', () {
      final v = valor(vender(lote: lote()));
      expect(v.loteId, 'L1');
      expect(v.data, '2026-03-12');
      expect(v.qtd, 50);
      expect(v.preco, 35.0);
    });

    test('sem compra escolhida', () {
      expect(
        erro(vender(lote: null)),
        'Escolha o ticker e a compra que foi vendida.',
      );
    });

    test('sem data', () {
      expect(
        erro(vender(lote: lote(), data: null)),
        'Selecione a data da venda.',
      );
    });

    test('data não permitida ou anterior à compra', () {
      expect(
        erro(vender(lote: lote(), permitida: false)),
        'Data da venda inválida para essa compra.',
      );
      expect(
        erro(vender(lote: lote(), data: '2026-03-09')),
        'Data da venda inválida para essa compra.',
      );
      expect(erro(vender(lote: lote(), data: '2026-03-10')), isNull);
    });

    test('quantidade inválida', () {
      for (final q in ['', 'x', '0', '2,5']) {
        expect(
          erro(vender(lote: lote(), qtd: q)),
          'Quantidade inválida.',
          reason: q,
        );
      }
    });

    test('quantidade maior que a disponível considera vendas anteriores', () {
      final l = lote(vendas: [venda(30, '2026-03-11')]);
      expect(
        erro(vender(lote: l, qtd: '71')),
        'Quantidade maior que a disponível (70).',
      );
      expect(erro(vender(lote: l, qtd: '70')), isNull);
    });

    test('preço inválido vem depois da quantidade', () {
      expect(erro(vender(lote: lote(), preco: 'abc')), 'Preço inválido.');
      expect(
        erro(vender(lote: lote(), qtd: '101', preco: 'abc')),
        'Quantidade maior que a disponível (100).',
      );
    });

    test('venda de mês anterior em compra que já tem venda no mês', () {
      final l = lote(
        dataCompra: '2026-02-10',
        vendas: [venda(10, '2026-03-05')],
      );
      expect(
        erro(vender(lote: l, data: '2026-02-20')),
        'Essa compra já tem venda neste mês. Para registrar uma venda de mês '
        'anterior, exclua a venda deste mês, registre a antiga e depois '
        'registre de novo a deste mês.',
      );
    });

    test('venda de mês anterior com meta ativa reservando quantidade', () {
      final l = lote(dataCompra: '2026-02-10');
      expect(
        erro(vender(lote: l, data: '2026-02-20', qtd: '41', reservado: 60)),
        'Há metas de venda ativas nessa compra. Quantidade livre: 40. '
        'Cancele ou ajuste a meta antes.',
      );
      expect(
        erro(vender(lote: l, data: '2026-02-20', qtd: '40', reservado: 60)),
        isNull,
      );
    });

    test('quantidade livre nunca aparece negativa', () {
      final l = lote(dataCompra: '2026-02-10');
      expect(
        erro(vender(lote: l, data: '2026-02-20', qtd: '1', reservado: 150)),
        'Há metas de venda ativas nessa compra. Quantidade livre: 0. '
        'Cancele ou ajuste a meta antes.',
      );
    });

    test('meta reservada não pesa em venda dentro do mês', () {
      expect(erro(vender(lote: lote(), qtd: '100', reservado: 100)), isNull);
    });

    test('editando: data de mês anterior é inválida (py:435-444)', () {
      final l = lote(
        dataCompra: '2026-02-10',
        vendas: [venda(10, '2026-03-05')],
      );
      expect(
        erro(
          vender(lote: l, data: '2026-02-20', reservado: 90, editando: true),
        ),
        'Data da venda inválida para essa compra.',
      );
      expect(erro(vender(lote: l, data: '2026-03-05', editando: true)), isNull);
    });
  });

  group('validarSaldo (calculadora_darf.py:570-580)', () {
    test('definir aceita zero e negativo', () {
      expect(valor(validarSaldo(ModoSaldo.definir, '10.000,50')), (
        ModoSaldo.definir,
        10000.5,
      ));
      expect(valor(validarSaldo(ModoSaldo.definir, '0')).$2, 0.0);
      expect(valor(validarSaldo(ModoSaldo.definir, '-250')).$2, -250.0);
    });

    test('valor inválido em qualquer modo', () {
      for (final m in ModoSaldo.values) {
        expect(erro(validarSaldo(m, 'abc')), 'Valor inválido.');
        expect(erro(validarSaldo(m, '')), 'Valor inválido.');
      }
    });

    test('aporte e retirada exigem valor maior que zero', () {
      for (final m in [ModoSaldo.aporte, ModoSaldo.retirada]) {
        expect(erro(validarSaldo(m, '0')), 'Informe um valor maior que zero.');
        expect(erro(validarSaldo(m, '-5')), 'Informe um valor maior que zero.');
        expect(valor(validarSaldo(m, '1.500')), (m, 1500.0));
      }
    });
  });

  group('textoTipo (calculadora_darf.py:272-274)', () {
    test('menos de 5 caracteres não mostra tipo', () {
      expect(textoTipo(''), isNull);
      expect(textoTipo('PETR'), isNull);
      expect(textoTipo('  pe  '), isNull);
    });

    test('ação, BDR e ticker em minúsculas com espaços', () {
      expect(textoTipo('PETR4'), 'Tipo: Ação (identificado pelo ticker)');
      expect(textoTipo(' aapl34 '), 'Tipo: BDR (identificado pelo ticker)');
    });
  });

  group('textosResumo (calculadora_darf.py:197-215)', () {
    test('sem resumo: nulo e texto de campos incompletos', () {
      expect(textosResumo(null), isNull);
      expect(textoResumoVazio, 'Preencha quantidade, preço e data.');
    });

    test('compra: debitado, IRRF zerado, liquidação em D+2', () {
      final res = resumoOrdem('compra', 100, 10, '2026-03-09');
      final r = textosResumo(res)!;
      expect(r.bruto, 'R\$ 1.000,00');
      expect(r.taxas, brl(res.taxas));
      expect(r.irrf, 'R\$ 0,00');
      expect(r.debito, isTrue);
      expect(r.impacto, 'Será debitado da conta: ${brl(-res.liquido)}');
      expect(
        r.liquidacao,
        '📅 Liquidação financeira: ${fmtLiquidacao('2026-03-11')}',
      );
      expect(fmtLiquidacao('2026-03-11'), contains('11/03/2026'));
    });

    test('venda swing: creditado', () {
      final res = resumoOrdem('venda', 100, 10, '2026-03-09', precoCompra: 5);
      final r = textosResumo(res)!;
      expect(r.debito, isFalse);
      expect(r.impacto, 'Será creditado na conta: ${brl(res.liquido)}');
    });

    test('venda com IRRF mostra o valor retido', () {
      final res = resumoOrdem('venda', 1000, 100, '2026-03-09', precoCompra: 5);
      expect(res.irrf, greaterThan(0));
      expect(textosResumo(res)!.irrf, brl(res.irrf));
    });

    test('notas de day trade e swing', () {
      expect(
        notaResumoCompra,
        'Se vender no mesmo dia (day trade), a B3 liquida só o resultado do '
        'dia.',
      );
      expect(
        notaResumoVenda(true),
        'Day trade (compra e venda no mesmo dia): a B3 liquida só o resultado, '
        'já com o IRRF de 1% sobre o lucro.',
      );
      expect(
        notaResumoVenda(false),
        'Swing trade: crédito do valor da venda menos as taxas da B3.',
      );
    });
  });

  group('textos dos KPIs (calculadora_darf.py:1583-1603)', () {
    test('textoInfoDarf: os três ramos e o limite de R\$ 10', () {
      expect(
        textoInfoDarf(apuracao(darf: 10), '2026-03'),
        'Código 6015 · vence no último dia útil de 04/2026',
      );
      expect(
        textoInfoDarf(apuracao(darf: 9.99), '2026-03'),
        'Abaixo de R\$ 10 · acumula para o próximo mês',
      );
      expect(
        textoInfoDarf(apuracao(darf: 0), '2026-03'),
        'Nada a pagar neste mês',
      );
    });

    test('N venda(s) no mês', () {
      expect(textoVendasNoMes(apuracao()), '0 vendas no mês');
      expect(textoVendasNoMes(apuracao(vendas: 1)), '1 venda no mês');
      expect(textoVendasNoMes(apuracao(vendas: 2)), '2 vendas no mês');
    });

    test('IRRF já retido', () {
      expect(
        textoIrrfRetido(apuracao(irrf: 12.5)),
        'IRRF já retido: R\$ 12,50',
      );
    });

    test('limite de isenção e situação', () {
      final dentro = apuracao(vendasAcoesSt: 5000);
      expect(textoLimiteIsencao(dentro), 'R\$ 5.000,00  de  R\$ 20.000,00');
      expect(textoIsencao(dentro), 'Isento de IR em swing trade de ações');
      final acima = apuracao(vendasAcoesSt: 25000, isento: false);
      expect(textoLimiteIsencao(acima), 'R\$ 25.000,00  de  R\$ 20.000,00');
      expect(textoIsencao(acima), 'Acima do limite · lucro tributado em 15%');
    });
  });

  group('venda por quantidade', () {
    Lote compra(String id, String data, int qtd, double preco) => Lote(
      id: id,
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: data,
      qtd: qtd,
      preco: preco,
    );
    final a = compra('A', '2026-10-02', 100, 30);
    final b = compra('B', '2026-10-05', 100, 20);
    final c = compra('C', '2026-10-28', 10, 40);

    Validacao<NovaVendaQtd> validar({
      String ticker = 'PETR4',
      String? data = '2026-10-28',
      String qtd = '150',
      String preco = '35,10',
      List<Lote>? elegiveis,
      Map<String, int>? selecao,
      bool permitida = true,
    }) => validarVendaQtd(
      ticker: ticker,
      data: data,
      qtd: qtd,
      preco: preco,
      inicioMes: '2026-10-01',
      permitida: permitida,
      elegiveis: elegiveis ?? [a, b],
      grupo: 'G1',
      selecao: selecao,
    );

    test('automático devolve o pedido sem seleção', () {
      final v = valor(validar());
      expect(v.ticker, 'PETR4');
      expect(v.data, '2026-10-28');
      expect(v.qtd, 150);
      expect(v.preco, 35.1);
      expect(v.grupo, 'G1');
      expect(v.selecao, isNull);
    });

    test('manual leva só as compras com quantidade', () {
      final v = valor(validar(selecao: {'A': 50, 'B': 100, 'C': 0}));
      expect(v.selecao, [('A', 50), ('B', 100)]);
    });

    test('mensagens', () {
      expect(
        erro(validar(elegiveis: [])),
        'Escolha o ticker e a compra que foi vendida.',
      );
      expect(erro(validar(data: null)), 'Selecione a data da venda.');
      expect(
        erro(validar(permitida: false)),
        'Data da venda inválida para essa compra.',
      );
      expect(
        erro(validar(data: '2026-09-30')),
        'Data da venda inválida para essa compra.',
      );
      expect(erro(validar(qtd: 'x')), 'Quantidade inválida.');
      expect(erro(validar(qtd: '0')), 'Quantidade inválida.');
      expect(erro(validar(preco: '')), 'Preço inválido.');
      expect(
        erro(validar(qtd: '300')),
        'Quantidade indisponível: só há 200 ações de PETR4 nessa data.',
      );
    });

    test('manual: soma diferente, acima do disponível e day trade travado', () {
      expect(
        erro(validar(selecao: {'A': 50, 'B': 50})),
        'A soma das compras escolhidas (100) é diferente da quantidade da '
        'venda (150).',
      );
      expect(
        erro(validar(qtd: '120', selecao: {'A': 120})),
        'A compra de 02/10/2026 tem só 100 ações disponíveis.',
      );
      expect(
        erro(validar(qtd: '50', elegiveis: [a, c], selecao: {'A': 50})),
        'As compras de hoje entram primeiro (day trade, regra da Receita).',
      );
    });

    test('resumoVendaPrevia soma o resumo de cada compra', () {
      final p = PreviaVenda(
        linhas: [
          LinhaPrevia(ItemAlocacao(b, 100), 20, 0),
          LinhaPrevia(ItemAlocacao(a, 50), 30, 0),
        ],
        gerencial: 0,
        fiscal: 0,
        qtdDt: 0,
        qtdComum: 150,
      );
      final r = resumoVendaPrevia(p, 35, '2026-10-28')!;
      final r1 = resumoOrdem('venda', 100, 35, '2026-10-28', precoCompra: 20);
      final r2 = resumoOrdem('venda', 50, 35, '2026-10-28', precoCompra: 30);
      expect(r.bruto, 5250);
      expect(r.taxas, r1.taxas + r2.taxas);
      expect(r.liquido, r1.liquido + r2.liquido);
      expect(r.liquidacao, r1.liquidacao);
      expect(
        resumoVendaPrevia(
          const PreviaVenda(
            linhas: [],
            gerencial: 0,
            fiscal: 0,
            qtdDt: 0,
            qtdComum: 0,
          ),
          35,
          '2026-10-28',
        ),
        isNull,
      );
    });

    test('resumoVendaPrevia aplica o limite de R\$ 1 do IRRF à soma', () {
      PreviaVenda previa(List<ItemAlocacao> itens) => PreviaVenda(
        linhas: [for (final i in itens) LinhaPrevia(i, 0, 0)],
        gerencial: 0,
        fiscal: 0,
        qtdDt: 0,
        qtdComum: 0,
      );
      // swing: 2 x 15.000 -> 0,75 por linha (abaixo do limite), 1,50 na soma
      final s = resumoVendaPrevia(
        previa([ItemAlocacao(a, 100), ItemAlocacao(b, 100)]),
        150,
        '2026-10-28',
      )!;
      expect(s.irrf, closeTo(1.5, 1e-9));
      expect(s.liquido, closeTo(s.bruto - s.taxas - 1.5, 1e-9));
      // day trade: ganho e perda se abatem antes do 1%
      final ganho = compra('G', '2026-10-28', 2000, 100);
      final perda = compra('P', '2026-10-28', 500, 200);
      final d = resumoVendaPrevia(
        previa([
          ItemAlocacao(ganho, 2000, travado: true),
          ItemAlocacao(perda, 500, travado: true),
        ]),
        150,
        '2026-10-28',
      )!;
      final r1 = resumoOrdem(
        'venda',
        2000,
        150,
        '2026-10-28',
        precoCompra: 100,
        dayTrade: true,
      );
      final r2 = resumoOrdem(
        'venda',
        500,
        150,
        '2026-10-28',
        precoCompra: 200,
        dayTrade: true,
      );
      final liquidoDia = r1.liquido + r1.irrf + r2.liquido + r2.irrf;
      expect(r2.liquido, lessThan(0));
      expect(d.irrf, closeTo(liquidoDia * 0.01, 1e-9));
      expect(d.liquido, closeTo(liquidoDia * 0.99, 1e-9));
      expect(d.dayTrade, isTrue);
    });

    test('textos fixos do painel', () {
      expect(textoSelecionado(120, 150), 'Selecionado 120 de 150');
      expect(
        textoResultadoGerencial(1234.5),
        'Resultado pelas compras escolhidas (gerencial): R\$ 1.234,50',
      );
      expect(
        textoResultadoFiscal(-10),
        'Resultado fiscal da operação (custo médio): -R\$ 10,00',
      );
      expect(
        textoResultadoFiscal(5, custoMedio: false),
        'Resultado fiscal da operação (por compra): R\$ 5,00',
      );
      expect(
        textoDayTradeComum(10, 140),
        'Day trade: 10 ações; comum: 140 ações',
      );
      expect(
        textoRegraAutomatico,
        'Primeiro as compras de hoje (day trade, regra da Receita). Depois as '
        'de menor custo por ação, incluindo as taxas de compra; em empate, a '
        'mais antiga.',
      );
      expect(
        textoEscolhaDasCompras,
        'A escolha das compras organiza o seu controle, mas não muda o '
        'imposto: a Receita usa o custo médio. Vender agora as compras mais '
        'baratas aumenta o resultado desta venda e reduz o das próximas; o '
        'resultado da posição inteira não muda.',
      );
      expect(
        textoEscolhaDasComprasPorCompra,
        'A escolha das compras organiza o seu controle. Este mês ainda é '
        'apurado por compra: o resultado fiscal acompanha as compras '
        'escolhidas. A partir do mês de corte, a Receita usa o custo médio e '
        'a escolha não muda o imposto.',
      );
    });
  });
}
