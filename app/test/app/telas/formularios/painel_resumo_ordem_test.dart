import 'package:calculadoradarf/app/telas/formularios/painel_resumo_ordem.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/montar_componente.dart';

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: '2026-10-28'));

  testWidgets('incompleto mostra traços e a mensagem', (t) async {
    await montarComponente(t, const PainelResumoOrdem(resumo: null));
    expect(find.text('RESUMO FINANCEIRO DA ORDEM'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('Preencha quantidade, preço e data.'), findsOneWidget);
  });

  testWidgets('compra mostra valores, débito e liquidação', (t) async {
    final r = resumoOrdem('compra', 100, 10, '2026-10-28');
    await montarComponente(
      t,
      PainelResumoOrdem(resumo: r, nota: 'Nota de teste.'),
    );
    expect(find.text('Valor bruto'), findsOneWidget);
    expect(find.text('Taxas B3 (estimadas)'), findsOneWidget);
    expect(find.text('IRRF retido'), findsOneWidget);
    expect(find.text(brl(1000)), findsOneWidget);
    expect(find.text('R\$ 0,00'), findsOneWidget);
    expect(
      find.text('Será debitado da conta: ${brl(-r.liquido)}'),
      findsOneWidget,
    );
    expect(find.text('Nota de teste.'), findsOneWidget);
    expect(find.textContaining('📅 Liquidação financeira: '), findsOneWidget);
  });

  testWidgets('venda mostra crédito', (t) async {
    final r = resumoOrdem('venda', 100, 10, '2026-10-28');
    await montarComponente(t, PainelResumoOrdem(resumo: r));
    expect(
      find.text('Será creditado na conta: ${brl(r.liquido)}'),
      findsOneWidget,
    );
  });
}
