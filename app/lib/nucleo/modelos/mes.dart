import 'com_mod.dart';
import 'lote.dart';

/// Apuração gravada no mês fechado (`d["resumo"]`, sem a lista `ops`).
class ResumoApuracao {
  ResumoApuracao({
    required this.vendasAcoesSt,
    required this.isento,
    required this.bruto,
    required this.custos,
    required this.impSt,
    required this.impDt,
    required this.impostoTotal,
    required this.irrf,
    required this.lucroLiquido,
    required this.darfMes,
    required this.darfAnterior,
    required this.darf,
  });

  factory ResumoApuracao.fromJson(Map<String, Object?> json) => ResumoApuracao(
    vendasAcoesSt: lerDouble(json['vendas_acoes_st']),
    isento: lerBool(json['isento']),
    bruto: lerDouble(json['bruto']),
    custos: lerDouble(json['custos']),
    impSt: lerDouble(json['imp_st']),
    impDt: lerDouble(json['imp_dt']),
    impostoTotal: lerDouble(json['imposto_total']),
    irrf: lerDouble(json['irrf']),
    lucroLiquido: lerDouble(json['lucro_liquido']),
    darfMes: lerDouble(json['darf_mes']),
    darfAnterior: lerDouble(json['darf_anterior']),
    darf: lerDouble(json['darf']),
  );

  double vendasAcoesSt;
  bool isento;
  double bruto;
  double custos;
  double impSt;
  double impDt;
  double impostoTotal;
  double irrf;
  double lucroLiquido;
  double darfMes;
  double darfAnterior;
  double darf;

  Map<String, Object?> toJson() => {
    'vendas_acoes_st': vendasAcoesSt,
    'isento': isento,
    'bruto': bruto,
    'custos': custos,
    'imp_st': impSt,
    'imp_dt': impDt,
    'imposto_total': impostoTotal,
    'irrf': irrf,
    'lucro_liquido': lucroLiquido,
    'darf_mes': darfMes,
    'darf_anterior': darfAnterior,
    'darf': darf,
  };
}

/// Marcador do mês apurado pelas regras da Receita (custo médio por ticker e
/// day trade por ativo no dia). Mês sem marcador usa o método por compra.
const metodoCustoMedio = 'custo_medio';

/// Posição de um ticker no custo médio: quantidade e custo total.
class PosicaoFiscal {
  PosicaoFiscal({required this.qtd, required this.custo});

  factory PosicaoFiscal.fromJson(Map<String, Object?> json) =>
      PosicaoFiscal(qtd: lerInt(json['qtd']), custo: lerDouble(json['custo']));

  int qtd;
  double custo;

  Map<String, Object?> toJson() => {'qtd': qtd, 'custo': custo};
}

/// Prejuízo a compensar trazido dos meses anteriores.
class PrejuizoAcumulado {
  PrejuizoAcumulado({this.comum = 0, this.dayTrade = 0});

  factory PrejuizoAcumulado.fromJson(Map<String, Object?> json) =>
      PrejuizoAcumulado(
        comum: lerDouble(json['comum']),
        dayTrade: lerDouble(json['day_trade']),
      );

  double comum;
  double dayTrade;

  Map<String, Object?> toJson() => {'comum': comum, 'day_trade': dayTrade};
}

/// Um arquivo `AAAA-MM.json`.
class Mes implements ComMod {
  Mes({
    required this.mes,
    this.fechado = false,
    this.darfAnterior = 0,
    List<Lote>? lotes,
    Map<String, double>? excluidos,
    this.mod = 0,
    this.resumo,
    this.retroativo = false,
    this.metodo,
    this.posicaoInicial,
    this.prejuizoAnterior,
  }) : lotes = lotes ?? [],
       excluidos = excluidos ?? {};

  /// Como `carregar`: `excluidos` ausente vira `{}`.
  factory Mes.fromJson(Map<String, Object?> json) => Mes(
    mes: lerTexto(json['mes']),
    fechado: lerBool(json['fechado']),
    darfAnterior: lerDouble(json['darf_anterior']),
    lotes: [for (final l in lerLista(json['lotes'])) Lote.fromJson(l)],
    excluidos: lerMapaDouble(json['excluidos']),
    mod: lerDouble(json['mod']),
    resumo: json['resumo'] is Map
        ? ResumoApuracao.fromJson(lerMapa(json['resumo']))
        : null,
    retroativo: lerBool(json['retroativo']),
    metodo: json['metodo'] is String ? json['metodo']! as String : null,
    posicaoInicial: json['posicao_inicial'] is Map
        ? {
            for (final e in lerMapa(json['posicao_inicial']).entries)
              e.key: PosicaoFiscal.fromJson(lerMapa(e.value)),
          }
        : null,
    prejuizoAnterior: json['prejuizo_anterior'] is Map
        ? PrejuizoAcumulado.fromJson(lerMapa(json['prejuizo_anterior']))
        : null,
  ).._ordem = json.keys.toList();

  String mes;
  bool fechado;
  double darfAnterior;
  List<Lote> lotes;

  /// Ids de registros excluídos -> momento da exclusão.
  Map<String, double> excluidos;
  @override
  double mod;
  ResumoApuracao? resumo;

  /// Mês criado por venda retroativa; só vai para o JSON quando verdadeiro.
  bool retroativo;

  /// Método de apuração do mês (`metodoCustoMedio`); nulo = por compra.
  String? metodo;

  /// Posição fiscal por ticker herdada do mês anterior (só no custo médio).
  Map<String, PosicaoFiscal>? posicaoInicial;

  /// Prejuízo a compensar herdado do mês anterior (só no custo médio).
  PrejuizoAcumulado? prejuizoAnterior;

  List<String>? _ordem;

  Map<String, Object?> toJson() => emOrdem({
    'mes': mes,
    'fechado': fechado,
    'darf_anterior': darfAnterior,
    'lotes': [for (final l in lotes) l.toJson()],
    'excluidos': {...excluidos},
    if (retroativo) 'retroativo': true,
    'mod': mod,
    if (resumo != null) 'resumo': resumo!.toJson(),
    if (metodo != null) 'metodo': metodo,
    if (posicaoInicial != null)
      'posicao_inicial': {
        for (final e in posicaoInicial!.entries) e.key: e.value.toJson(),
      },
    if (prejuizoAnterior != null)
      'prejuizo_anterior': prejuizoAnterior!.toJson(),
  }, _ordem);
}

/// `mes_vazio` (nucleo.py:121-122).
Mes mesVazio(String mes) => Mes(mes: mes);
