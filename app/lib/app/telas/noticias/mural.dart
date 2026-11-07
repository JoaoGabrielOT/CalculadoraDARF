// Regras puras do mural de notícias: estilo e altura estimada de cada cartão e
// a distribuição em colunas (calculadora_darf.py:999-1032, 2199-2216).

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';

/// Espaço entre cartões e colunas (py:2193).
const espacoMural = 16.0;

/// Largura mínima de uma coluna para contar como coluna (py:2194).
const _larguraColuna = 340;

/// Matérias desenhadas no mural (py:2164).
const maxMural = 60;

/// Proporção da imagem (altura/largura), fonte do título e limite do resumo
/// (`ESTILOS_NOTICIA`, py:1011).
enum EstiloNoticia {
  destaque(0.0, 22, 420),
  grande(0.6, 17, 260),
  medio(0.45, 15, 170),
  texto(0.0, 16, 320);

  const EstiloNoticia(this.proporcao, this.fonte, this.limite);

  final double proporcao;
  final double fonte;
  final int limite;
}

/// `cortar`: até [n] caracteres, sem partir palavra (py:999).
String cortar(String? texto, int n) {
  final t = (texto ?? '').trim();
  final pontos = t.runes.toList();
  if (pontos.length <= n) return t;
  final corte = String.fromCharCodes(pontos.take(n));
  final espaco = corte.lastIndexOf(' ');
  final inteiro = espaco < 0 ? corte : corte.substring(0, espaco);
  return '${inteiro.replaceFirst(RegExp(r'[,.;:–-]+$'), '')}…';
}

/// `linhas`: estimativa de linhas do [texto] numa [largura], para equilibrar
/// as colunas (py:1006).
int linhas(String? texto, double largura, double pxLetra) {
  if (texto == null || texto.isEmpty) return 0;
  final porLinha = (largura / pxLetra).truncate().clamp(10, 1 << 30);
  final n = texto.runes.length;
  final cheias = (n + porLinha - 1) ~/ porLinha;
  return cheias < 1 ? 1 : cheias;
}

/// `estilo_noticia`: sem imagem é texto; com tema ou entre as duas primeiras,
/// grande (py:1020).
EstiloNoticia estiloNoticia(Noticia item, DetalheNoticia? det, int indice) {
  if (det == null || det.img.isEmpty) return EstiloNoticia.texto;
  return item.temas.isNotEmpty || indice < 2
      ? EstiloNoticia.grande
      : EstiloNoticia.medio;
}

/// `altura_noticia`: altura estimada do cartão (py:1027).
double alturaNoticia(
  Noticia item,
  DetalheNoticia? det,
  EstiloNoticia estilo,
  double largura,
) {
  final resumo = cortar(det?.resumo, estilo.limite);
  final interna = largura - 36;
  return largura * estilo.proporcao +
      16 +
      linhas(item.titulo, interna, estilo.fonte * 0.55) * estilo.fonte * 1.45 +
      linhas(resumo, interna, 6.6) * 18 +
      96;
}

/// Quantas colunas cabem na [largura] do mural, de 1 a 4 (py:2194).
int colunasMural(double largura) =>
    ((largura + espacoMural) ~/ _larguraColuna).clamp(1, 4);

/// Cada item vai para a coluna mais baixa até ali (a primeira, no empate);
/// [altura] já inclui o espaço entre cartões (py:2201-2212).
List<List<Noticia>> distribuirMural(
  List<Noticia> itens,
  int colunas,
  double Function(Noticia) altura,
) {
  final saida = [for (var i = 0; i < colunas; i++) <Noticia>[]];
  final alturas = List<double>.filled(colunas, 0);
  for (final item in itens) {
    var menor = 0;
    for (var c = 1; c < colunas; c++) {
      if (alturas[c] < alturas[menor]) menor = c;
    }
    saida[menor].add(item);
    alturas[menor] += altura(item);
  }
  return saida;
}

/// O destaque do topo: entre as seis primeiras, a primeira com foto e tema,
/// senão a primeira com foto, senão a primeira matéria (py:2190).
Noticia escolherDestaque(
  List<Noticia> itens,
  Map<String, DetalheNoticia> detalhes,
) {
  final comFoto = [
    for (final i in itens.take(6))
      if ((detalhes[i.id]?.img ?? '').isNotEmpty) i,
  ];
  return comFoto.where((i) => i.temas.isNotEmpty).firstOrNull ??
      comFoto.firstOrNull ??
      itens.first;
}
