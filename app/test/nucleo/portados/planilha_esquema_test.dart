// Porte de tests/test_metas.py (TestMesclagem e TestCompatibilidadeStop): o que
// os testes afirmam sobre google_sync.ABAS vale aqui para esquemaAbas.

import 'package:calculadoradarf/nucleo/planilha/abas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TestMesclagem.test_aba_metas_no_google', () {
    expect(esquemaAbas.map((a) => a.nome), contains('Metas'));
    expect(esquemaDe('Metas').colunas, hasLength(14));
  });

  test('TestCompatibilidadeStop.test_planilha_tem_14_colunas_na_aba_metas', () {
    final metas = esquemaDe('Metas');
    expect(metas.colunas, hasLength(14));
    expect(
      [
        for (final c in metas.colunas.sublist(metas.colunas.length - 2))
          c.titulo,
      ],
      ['Gatilho', 'Detalhes'],
    );
  });
}
