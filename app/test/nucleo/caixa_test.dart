import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/caixa.dart';
import 'package:calculadoradarf/nucleo/compat/ordenacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

Repositorio _repo(Object? arquivos) {
  final memoria = ArmazenamentoMemoria();
  for (final e in _mapa(arquivos).entries) {
    memoria.gravar(e.key, jsonEncode(e.value));
  }
  return Repositorio(memoria);
}

Map<String, Object?> _item(LancamentoCaixa i) => {
  'id': i.id,
  'data': i.data,
  'ticker': i.ticker,
  'tipo': i.tipo,
  'qtd': i.qtd,
  'valor': i.valor,
  'liquidacao': i.liquidacao,
  if (i.status != null) 'status': i.status,
};

List<Object?> _itens(List<LancamentoCaixa> l) => [for (final i in l) _item(i)];

Map<String, Object?> _resumo(ResumoCaixa r) => {
  'definido': r.definido,
  'base': r.base,
  'saldo_base': r.saldoBase,
  'entrou': r.entrou,
  'disponivel': r.disponivel,
  'a_debitar': r.aDebitar,
  'a_receber': r.aReceber,
  'transito': r.transito,
  'projetado': r.projetado,
  'itens': _itens(r.itens),
};

List<Object?> _agenda(List<GrupoAgenda> g) => [
  for (final x in g)
    {
      'data': x.data,
      'rotulo': x.rotulo,
      'total': x.total,
      'itens': _itens(x.itens),
    },
];

List<Object?> _projecao(List<DiaProjecao> g) => [
  for (final x in g)
    {
      'data': x.data,
      'rotulo': x.rotulo,
      'total': x.total,
      'itens': _itens(x.itens),
      'saldo_apos': x.saldoApos,
    },
];

void _pascoaEFeriados(Caso caso, bool feriados) {
  final anos = [for (final a in _lista(_mapa(caso.entrada)['anos'])) a! as int];
  final esperado = _mapa(caso.saida);
  for (final ano in anos) {
    conferir(
      feriados ? ordenadoPor(feriadosB3(ano), (s) => [s]) : pascoa(ano),
      esperado['$ano'],
      caminho: '\$.$ano',
    );
  }
}

void _liquidacao(Caso caso) {
  final e = _mapa(caso.entrada);
  final n = (e['dias_uteis']! as num).toInt();
  for (final (i, l) in _lista(_mapa(caso.saida)['dias']).indexed) {
    final linha = _lista(l);
    final iso = linha[0]! as String;
    final liq = calcularDataLiquidacao(iso, diasUteis: n);
    conferir(
      [iso, diaUtil(iso), liq, fmtLiquidacao(liq)],
      linha,
      caminho: '\$.dias[$i]',
    );
  }
}

void _vencimentos(Caso caso) {
  final saida = _mapa(caso.saida);
  for (final h in _lista(_mapa(caso.entrada)['hojes'])) {
    final hoje = h! as String;
    final obtido = [
      for (final l in _lista(saida[hoje]))
        {
          'd': _mapa(l)['d'],
          'uteis_ate': diasUteisEntre(hoje, _mapa(l)['d']! as String),
          'uteis_de': diasUteisEntre(_mapa(l)['d']! as String, hoje),
          'rotulo': rotuloVencimento(_mapa(l)['d']! as String, hoje: hoje),
        },
    ];
    conferir(obtido, saida[hoje], caminho: '\$.$hoje');
  }
  // sem "hoje": usa o do ambiente (congelado em 2026-10-28)
  ambiente = Ambiente.fixo();
  conferir(
    [
      for (final l in _lista(saida['rotulo_sem_hoje']))
        {
          'd': _mapa(l)['d'],
          'rotulo': rotuloVencimento(_mapa(l)['d']! as String),
        },
    ],
    saida['rotulo_sem_hoje'],
    caminho: r'$.rotulo_sem_hoje',
  );
}

void _ordens(Caso caso) {
  final ordens = _lista(_mapa(caso.entrada)['ordens']);
  final esperados = _lista(_mapa(caso.saida)['resultados']);
  for (final (i, o) in ordens.indexed) {
    final e = _mapa(o);
    final r = resumoOrdem(
      e['lado']! as String,
      e['qtd']! as num,
      (e['preco']! as num).toDouble(),
      e['data']! as String,
      precoCompra: (e['preco_compra'] as num?)?.toDouble(),
      dayTrade: e['day_trade']! as bool,
    );
    conferir(
      {
        'bruto': r.bruto,
        'taxas': r.taxas,
        'irrf': r.irrf,
        'liquido': r.liquido,
        'day_trade': r.dayTrade,
        'liquidacao': r.liquidacao,
      },
      esperados[i],
      caminho: '\$.resultados[$i]',
    );
  }
}

Config _cfg(Map<String, Object?> caixa) => Config(caixa: Caixa.fromJson(caixa));

void _cenarios(Caso caso) {
  final entrada = _mapa(caso.entrada);
  final saida = _mapa(caso.saida);
  final meses = _repo(entrada['arquivos']).carregarMeses();
  conferir(
    _itens(lancamentosCaixa(meses)),
    saida['lancamentos'],
    caminho: r'$.lancamentos',
  );
  final esperados = _lista(saida['cenarios']);
  for (final (i, c) in _lista(entrada['cenarios']).indexed) {
    final cen = _mapa(c);
    final hoje = cen['hoje']! as String;
    final r = resumoCaixa(_cfg(_mapa(cen['caixa'])), meses, hoje: hoje);
    final esperado = _mapa(esperados[i]);
    final caminho = '\$.cenarios[$i]';
    conferir(_resumo(r), esperado['resumo'], caminho: '$caminho.resumo');
    conferir(
      _agenda(agendaCaixa(r, hoje: hoje)),
      esperado['agenda'],
      caminho: '$caminho.agenda',
    );
    conferir(
      _agenda(agendaCaixa(r, hoje: hoje, diasHistorico: 3)),
      esperado['agenda_curta'],
      caminho: '$caminho.agenda_curta',
    );
    conferir(
      _projecao(projecaoCaixa(r, hoje: hoje)),
      esperado['projecao'],
      caminho: '$caminho.projecao',
    );
  }
}

void _saldos(Caso caso) {
  final entrada = _mapa(caso.entrada);
  final repo = _repo(entrada['arquivos']);
  final cfg = Config.fromJson(_mapa(entrada['cfg']));
  final esperados = _lista(_mapa(caso.saida)['resultados']);
  ambiente = Ambiente.fixo();
  for (final (i, o) in _lista(entrada['operacoes']).indexed) {
    final op = _mapa(o);
    final hoje = op['hoje']! as String;
    if (op['op'] == 'definir') {
      definirSaldo(cfg, (op['valor']! as num).toDouble(), hoje: hoje);
    } else {
      ajustarSaldo(
        cfg,
        repo.carregarMeses(),
        (op['delta']! as num).toDouble(),
        hoje: hoje,
      );
    }
    conferir(cfg.caixa.toJson(), esperados[i], caminho: '\$.resultados[$i]');
  }
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('caixa'), startsWith('3.12'));
  });

  test('resumoCaixa valida a data do saldo como date.fromisoformat', () {
    for (final ruim in ['5/10/2026', 'lixo', '2026-02-30']) {
      expect(
        () => resumoCaixa(
          _cfg({'saldo': 10.0, 'data': ruim}),
          {},
          hoje: '2026-10-28',
        ),
        throwsFormatException,
        reason: ruim,
      );
    }
    final r = resumoCaixa(
      _cfg({'saldo': 10.0, 'data': '2026-10-05'}),
      {},
      hoje: '2026-10-28',
    );
    expect(r.definido, isTrue);
    expect(r.base, '2026-10-05');
    expect(
      resumoCaixa(_cfg({'saldo': 10.0}), {}, hoje: '2026-10-28').definido,
      isFalse,
    );
  });

  test('diasSemana', () {
    expect(diasSemana.length, 7);
    expect(diasSemana.first, 'Segunda-feira');
    expect(diasSemana.last, 'Domingo');
  });

  for (final caso in carregarCasos('caixa')) {
    test('${caso.funcao}: ${caso.nome}', () {
      switch (caso.funcao) {
        case 'pascoa':
          _pascoaEFeriados(caso, false);
        case 'feriados_b3':
          _pascoaEFeriados(caso, true);
        case 'liquidacao_dias':
          _liquidacao(caso);
        case 'vencimentos':
          _vencimentos(caso);
        case 'resumo_ordem':
          _ordens(caso);
        case 'cenarios_caixa':
          _cenarios(caso);
        case 'saldos':
          _saldos(caso);
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }
}
