import '../datas.dart';

/// Barra intradiária do Yahoo (`mercado.historico_desde`); `baixa` e `abre`
/// ficam nulas quando o Yahoo não as informa.
class Barra {
  Barra({
    required this.ts,
    required this.dt,
    required this.alta,
    this.baixa,
    this.abre,
  });

  final int ts;
  final DataHora dt;
  final double alta;
  final double? baixa;
  final double? abre;
}

/// Barra diária (`mercado.barras_diarias`); [data] é `AAAA-MM-DD`.
class BarraDiaria {
  BarraDiaria({
    required this.data,
    this.abre,
    required this.alta,
    required this.baixa,
    required this.fech,
  });

  final String data;
  final double? abre;
  final double alta;
  final double baixa;
  final double fech;
}

/// Barras diárias, com a data do último pregão em andamento e o preço atual.
class Diarias {
  Diarias({required this.barras, this.hoje, this.preco, this.fonte});

  final List<BarraDiaria> barras;
  final String? hoje;
  final double? preco;
  final String? fonte;
}

/// Resultado de `mercado.historico_desde`.
class HistoricoIntradiario {
  HistoricoIntradiario({
    required this.barras,
    required this.fonte,
    required this.intervalo,
    this.diarias,
  });

  final List<Barra> barras;
  final String fonte;
  final String intervalo;
  final Diarias? diarias;
}
