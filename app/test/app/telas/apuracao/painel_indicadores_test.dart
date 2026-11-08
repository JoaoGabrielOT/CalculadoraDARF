import 'package:calculadoradarf/app/telas/apuracao/painel_indicadores.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/montar_componente.dart';

IndicadoresAtivo _ind({String? metodo}) => IndicadoresAtivo(
  ticker: 'PETR4',
  qtdAberta: 0,
  custoRemanescente: null,
  custoPorCompra: true,
  metodoResultado: metodo,
  precoMedioCompras: null,
  precoMedioVendasMes: 12,
  resultadoMes: 199.34,
  resultadoAcumulado: 199.34,
  desde: '11/2026',
  ganhoPorUnidade: 1.9934,
  rentabilidadeRealizada: 0.1993,
  taxasMes: 0.36,
  pontoEquilibrio: null,
);

Future<void> _montar(WidgetTester t, IndicadoresAtivo i) => montarComponente(
  t,
  SingleChildScrollView(
    child: PainelIndicadores(indicadores: i, corrente: false),
  ),
  tamanho: const Size(800, 1400),
);

void main() {
  testWidgets('ativo zerado em mês de custo médio: rótulos fiscais', (t) async {
    await _montar(t, _ind(metodo: metodoCustoMedio));
    for (final r in [
      'Resultado realizado no mês (fiscal (custo médio), R\$)',
      'Resultado realizado acumulado desde 11/2026 (fiscal (custo médio), '
          'R\$)',
      'Rentabilidade realizada no mês (fiscal (custo médio), %)',
    ]) {
      expect(find.text(r), findsOneWidget, reason: r);
    }
    expect(find.textContaining('método por compra'), findsNothing);
  });

  testWidgets('mês por compra mantém "método por compra"', (t) async {
    await _montar(t, _ind());
    expect(
      find.text('Rentabilidade realizada no mês (método por compra, %)'),
      findsOneWidget,
    );
    expect(find.textContaining('custo médio'), findsNothing);
  });
}
