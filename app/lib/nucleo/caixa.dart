// Caixa e liquidação (D+2) na B3 (nucleo.py:538-739).

import 'alocacao.dart' show grupoDe;
import 'ambiente.dart';
import 'apuracao.dart';
import 'compat/numeros.dart';
import 'compat/ordenacao.dart';
import 'constantes.dart';
import 'datas.dart';
import 'modelos/config.dart';
import 'modelos/lote.dart';
import 'modelos/mes.dart';

const diasSemana = [
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
  'Domingo',
];

String _iso(int ano, int mes, int dia) =>
    isoDeDateTime(DateTime.utc(ano, mes, dia));

/// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher).
String pascoa(int ano) {
  final a = ano % 19;
  final b = ano ~/ 100;
  final c = ano % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = (h + l - 7 * m + 114) % 31 + 1;
  return _iso(ano, mes, dia);
}

final _cacheFeriados = <int, Set<String>>{};

/// Dias sem pregão na B3: feriados nacionais, Carnaval, Sexta-feira Santa,
/// Corpus Christi, 24 e 31/12.
Set<String> feriadosB3(int ano) => _cacheFeriados.putIfAbsent(ano, () {
  final p = pascoa(ano);
  const fixos = [
    (1, 1),
    (4, 21),
    (5, 1),
    (9, 7),
    (10, 12),
    (11, 2),
    (11, 15),
    (12, 24),
    (12, 25),
    (12, 31),
  ];
  final dias = {for (final (m, d) in fixos) _iso(ano, m, d)};
  if (ano >= 2024) dias.add(_iso(ano, 11, 20)); // Consciência Negra
  dias.addAll([
    somarDias(p, -48),
    somarDias(p, -47),
    somarDias(p, -2),
    somarDias(p, 60),
  ]);
  return Set.unmodifiable(dias);
});

bool diaUtil(String iso) =>
    diaDaSemana(iso) < 5 &&
    !feriadosB3(int.parse(iso.substring(0, 4))).contains(iso);

/// Data de liquidação financeira na B3: D+2 em dias úteis.
String calcularDataLiquidacao(
  String dataOperacao, {
  int diasUteis = diasLiquidacao,
}) {
  var d = dataOperacao;
  var n = 0;
  while (n < diasUteis) {
    d = somarDias(d, 1);
    if (diaUtil(d)) n++;
  }
  return d;
}

String fmtLiquidacao(String iso) =>
    '${diasSemana[diaDaSemana(iso)]}, ${fmtData(iso)}';

/// Quantos dias úteis há depois de [inicio] até [fim] (0 se fim <= inicio).
int diasUteisEntre(String inicio, String fim) {
  var n = 0;
  var d = inicio;
  while (d.compareTo(fim) < 0) {
    d = somarDias(d, 1);
    if (diaUtil(d)) n++;
  }
  return n;
}

/// Rótulo do agrupamento da agenda: Hoje, Amanhã (D+1), Depois de amanhã
/// (D+2) ou o dia da semana.
String rotuloVencimento(String d, {String? hoje}) {
  hoje ??= ambiente.hoje();
  if (d.compareTo(hoje) < 0) return 'Liquidado em ${fmtData(d)}';
  if (d == hoje) return 'Hoje';
  final n = diasUteisEntre(hoje, d);
  final String nome;
  if (d == somarDias(hoje, 1)) {
    nome = 'Amanhã';
  } else if (d == somarDias(hoje, 2)) {
    nome = 'Depois de amanhã';
  } else {
    nome = '${diasSemana[diaDaSemana(d)]}, ${fmtData(d).substring(0, 5)}';
  }
  return '$nome (D+$n)';
}

/// Impacto financeiro de uma ordem (`resumo_ordem`).
class ResumoOrdem {
  ResumoOrdem({
    required this.bruto,
    required this.taxas,
    required this.irrf,
    required this.liquido,
    required this.dayTrade,
    required this.liquidacao,
  });

  final double bruto;
  final double taxas;
  final double irrf;
  final double liquido;
  final bool dayTrade;
  final String liquidacao;
}

/// [lado]: "compra" ou "venda". Na venda em day trade, informe o preço de
/// compra: a B3 liquida só o resultado do dia.
ResumoOrdem resumoOrdem(
  String lado,
  num qtd,
  double preco,
  String dataOperacao, {
  double? precoCompra,
  bool dayTrade = false,
}) {
  final bruto = qtd * preco;
  var irrf = 0.0;
  final double taxas;
  final double liquido;
  if (lado == 'compra') {
    taxas = bruto * taxaB3Swing;
    liquido = -(bruto + taxas);
  } else if (dayTrade) {
    final compra = qtd * (precoCompra ?? 0.0);
    taxas = (bruto + compra) * taxaB3Daytrade;
    final resultado = bruto - compra - taxas;
    irrf = resultado * irrfDaytrade > 1 ? resultado * irrfDaytrade : 0.0;
    liquido = resultado - irrf;
  } else {
    taxas = bruto * taxaB3Swing;
    irrf = bruto * irrfSwing > 1 ? bruto * irrfSwing : 0.0;
    liquido = bruto - taxas - irrf;
  }
  return ResumoOrdem(
    bruto: bruto,
    taxas: taxas,
    irrf: irrf,
    liquido: liquido,
    dayTrade: dayTrade && lado != 'compra',
    liquidacao: calcularDataLiquidacao(dataOperacao),
  );
}

/// Movimento financeiro de uma operação gravada.
class LancamentoCaixa {
  LancamentoCaixa({
    required this.id,
    required this.data,
    required this.ticker,
    required this.tipo,
    required this.qtd,
    required this.valor,
    required this.liquidacao,
    this.status,
  });

  final String id;
  final String data;
  final String ticker;
  final String tipo;
  final int qtd;
  final double valor;
  final String liquidacao;

  /// "Liquidado" ou "Pendente"; preenchido por [resumoCaixa].
  String? status;
}

/// Movimentos financeiros de todas as operações de [meses], com data de
/// liquidação (D+2).
///
/// Compra (parte que não virou day trade): -(valor + taxas B3). Venda swing:
/// +(valor - taxas B3). Day trade: só o resultado do dia. IRRF retido entra
/// como débito no dia. Compras levadas de um mês para o outro (origem) não
/// geram novo débito.
List<LancamentoCaixa> lancamentosCaixa(Map<String, Mes> meses) {
  final itens = <LancamentoCaixa>[];
  final irrfStDia = <String, double>{};
  final resDtDia = <String, double>{};
  // venda em várias compras (ids `<grupo>.<k>`): um lançamento por grupo e
  // regime, na posição da primeira linha; o IRRF do dia segue por linha
  final posicaoGrupo = <String, int>{};

  void adicionar(
    String id,
    String data,
    String ticker,
    String tipo,
    int qtd,
    double valor,
  ) => itens.add(
    LancamentoCaixa(
      id: id,
      data: data,
      ticker: ticker,
      tipo: tipo,
      qtd: qtd,
      valor: valor,
      liquidacao: calcularDataLiquidacao(data),
    ),
  );

  void adicionarVenda(Venda v, String ticker, String tipo, double valor) {
    final grupo = grupoDe(v.id);
    final chave = '$grupo|$tipo';
    final i = posicaoGrupo[chave];
    if (i == null) {
      final outro = posicaoGrupo.containsKey(
        '$grupo|${tipo == 'Venda' ? 'Day trade' : 'Venda'}',
      );
      posicaoGrupo[chave] = itens.length;
      adicionar(
        outro ? 'v:$grupo:${tipo == 'Venda' ? 'st' : 'dt'}' : 'v:$grupo',
        v.data,
        ticker,
        tipo,
        v.qtd,
        valor,
      );
      return;
    }
    final x = itens[i];
    itens[i] = LancamentoCaixa(
      id: x.id,
      data: x.data,
      ticker: x.ticker,
      tipo: x.tipo,
      qtd: x.qtd + v.qtd,
      valor: x.valor + valor,
      liquidacao: x.liquidacao,
    );
  }

  for (final chave in ordenadoPor(meses.keys, (m) => [m])) {
    for (final l in meses[chave]!.lotes) {
      if (l.origem == null || l.origem!.isEmpty) {
        final q =
            l.qtd -
            l.vendas
                .where((v) => v.data == l.dataCompra)
                .fold<int>(0, (s, v) => s + v.qtd);
        if (q > 0) {
          final bruto = q * l.preco;
          adicionar(
            'c:${l.id}',
            l.dataCompra,
            l.ticker,
            'Compra',
            q,
            -(bruto + bruto * taxaB3Swing),
          );
        }
      }
      for (final v in l.vendas) {
        final c = calcularVenda(l, v);
        if (c.dt) {
          resDtDia[v.data] = (resDtDia[v.data] ?? 0.0) + c.liquido;
          adicionarVenda(v, l.ticker, 'Day trade', c.liquido);
        } else {
          irrfStDia[v.data] = (irrfStDia[v.data] ?? 0.0) + c.venda * irrfSwing;
          adicionarVenda(v, l.ticker, 'Venda', c.venda - c.venda * taxaB3Swing);
        }
      }
    }
  }
  for (final e in irrfStDia.entries) {
    if (e.value > 1) {
      adicionar(
        'irrf:st:${e.key}',
        e.key,
        'IRRF',
        'IRRF (dedo-duro)',
        0,
        -e.value,
      );
    }
  }
  for (final e in resDtDia.entries) {
    if (e.value * irrfDaytrade > 1) {
      adicionar(
        'irrf:dt:${e.key}',
        e.key,
        'IRRF',
        'IRRF day trade',
        0,
        -e.value * irrfDaytrade,
      );
    }
  }
  return ordenadoPor(itens, (x) => [x.liquidacao, x.data, x.ticker]);
}

/// Saldo disponível (D+0), em trânsito e projetado (`resumo_caixa`).
class ResumoCaixa {
  ResumoCaixa({
    required this.definido,
    required this.base,
    required this.saldoBase,
    required this.entrou,
    required this.disponivel,
    required this.aDebitar,
    required this.aReceber,
    required this.transito,
    required this.projetado,
    required this.itens,
  });

  final bool definido;
  final String? base;
  final double saldoBase;
  final double entrou;
  final double disponivel;
  final double aDebitar;
  final double aReceber;
  final double transito;
  final double projetado;
  final List<LancamentoCaixa> itens;
}

/// O saldo informado vale para o dia em que foi definido e já inclui o que
/// liquidou até esse dia. O que liquida depois disso é somado ao disponível
/// quando a data chega (status Liquidado).
ResumoCaixa resumoCaixa(Config cfg, Map<String, Mes> meses, {String? hoje}) {
  hoje ??= ambiente.hoje();
  final caixa = cfg.caixa;
  // `date.fromisoformat`: data inválida lança; AAAAMMDD vira AAAA-MM-DD
  final base = caixa.data.isNotEmpty ? somarDias(caixa.data, 0) : null;
  final saldo = caixa.saldo;
  final itens = lancamentosCaixa(meses);
  var entrou = 0.0;
  for (final it in itens) {
    it.status = it.liquidacao.compareTo(hoje) <= 0 ? 'Liquidado' : 'Pendente';
    if (base != null &&
        base.compareTo(it.liquidacao) < 0 &&
        it.liquidacao.compareTo(hoje) <= 0) {
      entrou += it.valor;
    }
  }
  final pendentes = [
    for (final it in itens)
      if (it.status == 'Pendente') it,
  ];
  final aDebitar = somaPython([
    for (final it in pendentes)
      if (it.valor < 0) it.valor,
  ]);
  final aReceber = somaPython([
    for (final it in pendentes)
      if (it.valor > 0) it.valor,
  ]);
  final disponivel = saldo + entrou;
  return ResumoCaixa(
    definido: base != null,
    base: base,
    saldoBase: saldo,
    entrou: entrou,
    disponivel: disponivel,
    aDebitar: aDebitar,
    aReceber: aReceber,
    transito: aDebitar + aReceber,
    projetado: disponivel + aDebitar + aReceber,
    itens: itens,
  );
}

typedef GrupoAgenda = ({
  String data,
  String rotulo,
  double total,
  List<LancamentoCaixa> itens,
});

/// Lançamentos pendentes e os liquidados nos últimos [diasHistorico] dias,
/// agrupados pela data de liquidação.
List<GrupoAgenda> agendaCaixa(
  ResumoCaixa r, {
  String? hoje,
  int diasHistorico = 15,
}) {
  hoje ??= ambiente.hoje();
  final limite = somarDias(hoje, -diasHistorico);
  final grupos = <String, List<LancamentoCaixa>>{};
  for (final it in r.itens) {
    if (it.liquidacao.compareTo(limite) > 0) {
      grupos.putIfAbsent(it.liquidacao, () => []).add(it);
    }
  }
  return [
    for (final d in ordenadoPor(grupos.keys, (k) => [k]))
      (
        data: d,
        rotulo: rotuloVencimento(d, hoje: hoje),
        total: somaPython([for (final i in grupos[d]!) i.valor]),
        itens: grupos[d]!,
      ),
  ];
}

typedef DiaProjecao = ({
  String data,
  String rotulo,
  double total,
  List<LancamentoCaixa> itens,
  double saldoApos,
});

/// Liquidações pendentes por data, com o saldo que sobra depois de cada uma.
List<DiaProjecao> projecaoCaixa(ResumoCaixa r, {String? hoje}) {
  hoje ??= ambiente.hoje();
  var saldo = r.disponivel;
  final saida = <DiaProjecao>[];
  for (final g in agendaCaixa(r, hoje: hoje)) {
    if (g.data.compareTo(hoje) > 0) {
      saldo += g.total;
      saida.add((
        data: g.data,
        rotulo: g.rotulo,
        total: g.total,
        itens: g.itens,
        saldoApos: saldo,
      ));
    }
  }
  return saida;
}

/// Define o saldo disponível de hoje (o que já liquidou até hoje deve estar
/// incluído).
void definirSaldo(Config cfg, double valor, {String? hoje}) {
  hoje ??= ambiente.hoje();
  cfg.caixa = Caixa(
    saldo: arredondar(valor, 2),
    data: hoje,
    mod: ambiente.agora(),
  );
}

/// Aporte (delta > 0) ou retirada (delta < 0) sobre o saldo disponível atual.
void ajustarSaldo(
  Config cfg,
  Map<String, Mes> meses,
  double delta, {
  String? hoje,
}) {
  final atual = resumoCaixa(cfg, meses, hoje: hoje).disponivel;
  definirSaldo(cfg, atual + delta, hoje: hoje);
}
