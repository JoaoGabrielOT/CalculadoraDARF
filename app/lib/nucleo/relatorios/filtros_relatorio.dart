// Filtro puro dos ativos do Relatório de Abertura e do período da lista dos
// anteriores. Dentro de cada grupo (tipo, leitura) a seleção é OU; entre os
// grupos é E. Filtro vazio devolve a lista como veio.

import '../datas.dart';
import '../noticias/texto.dart' show semAcento;
import 'destaques.dart';
import 'relatorio.dart';
import 'selecao.dart';

class FiltroAtivos {
  const FiltroAtivos({
    this.texto = '',
    this.tipos = const {},
    this.leituras = const {},
    this.comAnalise,
    this.soDestaque = false,
    this.soCarteira = false,
  });

  /// Busca em ticker, empresa e descrição, sem acento e sem caixa.
  final String texto;

  /// Valores de `tipoAtivo` já em minúsculas (ver [chaveTipo]).
  final Set<String> tipos;
  final Set<Leitura> leituras;

  /// true = só com análise; false = só sem; null = tanto faz.
  final bool? comAnalise;
  final bool soDestaque;
  final bool soCarteira;

  bool get vazio =>
      texto.trim().isEmpty &&
      tipos.isEmpty &&
      leituras.isEmpty &&
      comAnalise == null &&
      !soDestaque &&
      !soCarteira;

  FiltroAtivos copiar({
    String? texto,
    Set<String>? tipos,
    Set<Leitura>? leituras,
    bool? Function()? comAnalise,
    bool? soDestaque,
    bool? soCarteira,
  }) => FiltroAtivos(
    texto: texto ?? this.texto,
    tipos: tipos ?? this.tipos,
    leituras: leituras ?? this.leituras,
    comAnalise: comAnalise != null ? comAnalise() : this.comAnalise,
    soDestaque: soDestaque ?? this.soDestaque,
    soCarteira: soCarteira ?? this.soCarteira,
  );
}

/// Tipo do ativo como chave de comparação; sem tipo, null.
String? chaveTipo(AtivoRelatorio a) {
  final t = a.tipoAtivo?.trim().toLowerCase();
  return t == null || t.isEmpty ? null : t;
}

/// Alguma casa com algo a mostrar (a mesma ideia do bloco dos especialistas).
bool temAnalise(AtivoRelatorio a) => a.especialistas.itens.any(
  (i) =>
      votoDoItem(i) != null ||
      i.casa != null ||
      i.data != null ||
      i.motivo != null ||
      i.recomendacao != null ||
      i.url != null,
);

/// Mantém a ordem recebida. [carteira] são os tickers com posição aberta.
List<AtivoRelatorio> filtrarAtivos(
  List<AtivoRelatorio> ativos,
  FiltroAtivos f, {
  Set<String> carteira = const {},
}) {
  if (f.vazio) return ativos;
  final busca = semAcento(f.texto.trim());
  final carteiraMaiuscula = {for (final t in carteira) t.toUpperCase()};
  bool passa(AtivoRelatorio a) {
    if (busca.isNotEmpty &&
        ![
          a.ticker,
          a.empresa,
          a.descricao,
        ].any((s) => semAcento(s).contains(busca))) {
      return false;
    }
    if (f.tipos.isNotEmpty && !f.tipos.contains(chaveTipo(a))) return false;
    if (f.leituras.isNotEmpty && !f.leituras.contains(a.leitura)) return false;
    if (f.comAnalise != null && temAnalise(a) != f.comAnalise) return false;
    if (f.soDestaque && !emDestaque(a)) return false;
    if (f.soCarteira && !carteiraMaiuscula.contains(a.ticker.toUpperCase())) {
      return false;
    }
    return true;
  }

  return [
    for (final a in ativos)
      if (passa(a)) a,
  ];
}

/// Relatórios dos últimos [dias] dias (a data de [hoje] inclusive); null = todos.
List<ResumoRelatorio> filtrarPorPeriodo(
  List<ResumoRelatorio> itens,
  int? dias,
  String hoje,
) {
  if (dias == null) return itens;
  final corte = somarDias(hoje, -dias);
  return [
    for (final i in itens)
      if (i.data.compareTo(corte) >= 0) i,
  ];
}
