import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/relatorios/selecao.dart';
import 'package:flutter_test/flutter_test.dart';

ResumoRelatorio _r(String data) =>
    ResumoRelatorio(nome: 'relatorio-abertura-$data.json', data: data);

void main() {
  test('data pelo nome do arquivo', () {
    expect(dataDoNome('relatorio-abertura-2026-11-26.json'), '2026-11-26');
    for (final n in [
      'relatorio-abertura-2026-02-30.json',
      'relatorio-abertura-2026-11-26.json.bak',
      'copia relatorio-abertura-2026-11-26.json',
      'relatorio-abertura-26-11-2026.json',
      '',
    ]) {
      expect(dataDoNome(n), isNull, reason: n);
    }
  });
  test('hoje no fuso de Brasília (UTC−3 fixo)', () {
    expect(hojeBrasilia(DataHora.parse('2026-11-27T02:00:00Z')), '2026-11-26');
    expect(hojeBrasilia(DataHora.parse('2026-11-27T03:00:00Z')), '2026-11-27');
    expect(
      hojeBrasilia(DataHora.parse('2026-11-26T23:59:00-03:00')),
      '2026-11-26',
    );
  });
  test('escolha: existe o de hoje', () {
    final l = ordenarRelatorios([
      _r('2026-11-25'),
      _r('2026-11-26'),
      _r('2026-11-24'),
    ]);
    expect(l.map((r) => r.data), ['2026-11-26', '2026-11-25', '2026-11-24']);
    final e = escolherRelatorio(l, '2026-11-26');
    expect((e.escolhido!.data, e.ehHoje), ('2026-11-26', true));
  });
  test('escolha: hoje não existe, cai no mais recente', () {
    final e = escolherRelatorio(
      ordenarRelatorios([_r('2026-11-24'), _r('2026-11-25')]),
      '2026-11-26',
    );
    expect((e.escolhido!.data, e.ehHoje), ('2026-11-25', false));
    expect(escolherRelatorio(const [], '2026-11-26').escolhido, isNull);
  });
  test('data por extenso', () {
    expect(
      dataPorExtenso('2026-11-26'),
      'Quinta-feira, 26 de novembro de 2026',
    );
    expect(dataPorExtenso('2026-03-01'), 'Domingo, 1 de março de 2026');
  });
}
