// Detecção do gatilho de metas (alvo e stop) e stop móvel (metas.py:358-417).

import '../compat/numeros.dart';
import '../compat/ordenacao.dart';
import '../datas.dart';
import '../erros.dart';
import '../mercado/indicadores.dart';
import '../modelos/barras.dart';
import '../modelos/meta.dart';
import 'preco_alvo.dart';

/// `piso_centavo` com a garantia do Python: `math.floor` lança para NaN e
/// infinito, enquanto o Dart devolveria NaN/infinito em silêncio.
double _pisoFinito(double v) {
  if (!v.isFinite) throw ErroValidacao('Valor não finito: $v');
  return pisoCentavo(v);
}

/// Primeira barra (em ordem de tempo) que começa depois da criação da meta e
/// cuja máxima chegou ao alvo.
Barra? acharBarra(List<Barra> barras, double precoAlvo, DataHora criadaEm) {
  for (final b in ordenadoCom(barras, (a, b) => a.dt.compareTo(b.dt))) {
    if (b.dt >= criadaEm && b.alta + 1e-9 >= precoAlvo) return b;
  }
  return null;
}

/// Stop em vigor numa data (`AAAA-MM-DD`): o maior nível cujo "desde" não é
/// posterior a ela.
double? nivelVigente(List<Nivel> niveis, String dataIso) {
  final validos = [
    for (final n in niveis)
      if (compararTexto(n.desde, dataIso) <= 0) n.stop,
  ];
  return validos.isEmpty ? null : maxDe(validos);
}

/// Primeira barra que começa depois da criação do stop e cuja mínima chegou ao
/// stop vigente na data dela. Retorna (barra, stop vigente) ou nulo. Barras
/// sem mínima válida não contam.
(Barra, double)? acharBarraStop(
  List<Barra> barras,
  List<Nivel> niveis,
  DataHora criadaEm,
) {
  for (final b in ordenadoCom(barras, (a, b) => a.dt.compareTo(b.dt))) {
    final baixa = b.baixa;
    if (b.dt < criadaEm || baixa == null) continue;
    final nivel = nivelVigente(niveis, b.dt.data);
    if (nivel != null && baixa <= nivel + 1e-9) return (b, nivel);
  }
  return null;
}

/// Preço em que o app registra a venda do stop: o próprio stop, ou a abertura
/// quando a barra abriu abaixo dele (gap de baixa, pior preço plausível).
/// Retorna (preço, houve_gap).
(double, bool) precoExecucaoStop(Barra barra, double nivel) {
  final abre = barra.abre;
  if (abre != null && abre < nivel - 1e-9) {
    return (maxPython(_pisoFinito(abre), 0.01), true);
  }
  return (nivel, false);
}

/// Sobe o stop móvel (Chandelier Exit de 22 pregões, 3 ATR) com os pregões
/// fechados desde a criação da meta. [barras]: diárias do mercado; [hoje]
/// (`AAAA-MM-DD`): só conta data < hoje. Cada nível novo vale a partir do dia
/// seguinte ao pregão que o calculou; o stop nunca desce e, sem dados
/// suficientes, fica como está. Retorna true se acrescentou algum nível.
/// Repetir a chamada não muda nada. O Chandelier de todos os pregões sai de
/// uma passada só ([serie], por padrão `serieChandelier`).
bool atualizarStopMovel(
  Meta meta,
  List<BarraDiaria> barras,
  String hoje, {
  List<double?> Function(List<BarraDiaria>) serie = serieChandelier,
}) {
  if (gatilho(meta) != 'stop' || meta.movel != true) return false;
  final criada = DataHora.parse(meta.criadaEm).data;
  final fechadas = ordenadoPor(
    barras.where((b) => compararTexto(b.data, hoje) < 0),
    (b) => [b.data],
  );
  final niveis = meta.niveis ??= [];
  var ultimo = maxDe([for (final n in niveis) n.stop, meta.stopAtual!]);
  var mudou = false;
  final chandelier = serie(fechadas);
  for (var i = 0; i < fechadas.length && i < chandelier.length; i++) {
    final b = fechadas[i];
    final c = chandelier[i];
    if (compararTexto(b.data, criada) < 0 || c == null) continue;
    final novo = _pisoFinito(c);
    if (novo > ultimo + 1e-9) {
      niveis.add(
        Nivel(desde: somarDias(b.data, 1), stop: novo, calcEm: b.data),
      );
      ultimo = novo;
      mudou = true;
    }
  }
  if (mudou) meta.stopAtual = ultimo;
  return mudou;
}
