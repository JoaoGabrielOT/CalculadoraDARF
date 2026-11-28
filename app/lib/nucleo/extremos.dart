// Melhor e pior resultado possível de uma venda, a partir da máxima e da
// mínima das cotações diárias. Análise complementar: não altera o resultado
// oficial, o imposto nem o DARF.

import 'apuracao.dart';
import 'modelos/barras.dart';
import 'modelos/lote.dart';

/// Preço de um extremo e o dia (`AAAA-MM-DD`) em que ocorreu.
class Extremo {
  const Extremo({required this.preco, required this.data});

  final double preco;
  final String data;
}

class Extremos {
  const Extremos({required this.maximo, required this.minimo});

  final Extremo maximo;
  final Extremo minimo;
}

/// Máxima das altas e mínima das baixas das barras entre [desde] e [ate]
/// (inclusive, `AAAA-MM-DD`); nulo sem nenhuma barra no intervalo.
Extremos? extremosDe(List<BarraDiaria> barras, String desde, String ate) {
  Extremo? maximo;
  Extremo? minimo;
  for (final b in barras) {
    if (b.data.compareTo(desde) < 0 || b.data.compareTo(ate) > 0) continue;
    if (maximo == null || b.alta > maximo.preco) {
      maximo = Extremo(preco: b.alta, data: b.data);
    }
    if (minimo == null || b.baixa < minimo.preco) {
      minimo = Extremo(preco: b.baixa, data: b.data);
    }
  }
  if (maximo == null || minimo == null) return null;
  return Extremos(maximo: maximo, minimo: minimo);
}

/// Resultado líquido de vender [qtd] do [lote] no extremo [e]: a mesma
/// fórmula da apuração, só com o preço e o dia trocados.
double resultadoHipotetico(Lote lote, int qtd, Extremo e) =>
    calcularVendaQtd(lote, qtd, e.preco, e.data).liquido;
