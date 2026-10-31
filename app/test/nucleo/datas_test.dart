import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

/// Executa [f]; se o Python gravou `{"erro": ...}`, o Dart deve lançar
/// `FormatException` (ValueError) e o caso termina aqui.
void _comErro(Object? saida, Object? Function() f, void Function(Object?) ok) {
  if (saida is Map && saida.containsKey('erro')) {
    expect(f, throwsFormatException);
    return;
  }
  ok(f());
}

Map<String, Object?> _resumo(DataHora d) => {
  'ts': d.timestamp,
  'desvio': d.desvio,
  'data': d.data,
  'hora': d.horaMinuto,
  'iso': d.iso(),
};

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('datas'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('datas')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = caso.entrada! as Map<String, Object?>;
      switch (caso.funcao) {
        case 'de_serial':
          _comErro(
            caso.saida,
            () => deSerial(e['v']),
            (r) => conferir(r, caso.saida),
          );
        case 'mes_iso':
          _comErro(
            caso.saida,
            () => mesIso(e['v']),
            (r) => conferir(r, caso.saida),
          );
        case 'serial':
          conferir(serial(e['iso']! as String), caso.saida);
        case 'proximo_mes':
          conferir(proximoMes(e['mes']! as String), caso.saida);
        case 'limites_mes':
          final (a, b) = limitesMes(e['mes']! as String);
          conferir([a, b], caso.saida);
        case 'fmt_data':
          conferir(fmtData(e['iso']! as String), caso.saida);
        case 'fmt_mes':
          conferir(fmtMes(e['mes']! as String), caso.saida);
        case 'weekday':
          conferir(diaDaSemana(e['iso']! as String), caso.saida);
        case 'fromisoformat':
          _comErro(
            caso.saida,
            () => _resumo(DataHora.parse(e['texto']! as String)),
            (r) => conferir(r, caso.saida),
          );
          final tentativa = DataHora.tentarParse(e['texto']! as String);
          expect(
            tentativa == null,
            caso.saida is Map && (caso.saida! as Map).containsKey('erro'),
          );
        case 'fromtimestamp':
          conferir(
            _resumo(DataHora.deTimestamp(e['ts']! as num, fusoBrasilia)),
            caso.saida,
          );
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }

  test('DataHora.iso volta para -03:00 como metas.iso', () {
    expect(
      DataHora.parse('2026-10-20T14:00:00Z').noFuso(fusoBrasilia).iso(),
      '2026-10-20T11:00:00-03:00',
    );
  });

  test('somarDias e diasEntre atravessam mês, ano e bissexto', () {
    expect(somarDias('2024-02-28', 2), '2024-03-01');
    expect(somarDias('2026-01-01', -1), '2025-12-31');
    expect(diasEntre('2026-10-01', '2026-10-28'), 27);
    expect(diasEntre('2026-10-28', '2026-10-01'), -27);
  });

  test('isoDeDateTime usa a data do próprio DateTime', () {
    expect(isoDeDateTime(DateTime.utc(2026, 3, 7, 23, 59)), '2026-03-07');
  });

  test('parseData e deSerial rejeitam datas inexistentes', () {
    expect(() => parseData('31/02/2026'), throwsFormatException);
    expect(() => deSerial('x'), throwsFormatException);
    expect(() => deSerial(true), throwsFormatException);
  });

  test('DataHora compara pelo instante, não pelo fuso', () {
    final a = DataHora.parse('2026-10-20T11:00:00-03:00');
    final b = DataHora.parse('2026-10-20T14:00:00Z');
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
    expect(a < DataHora.parse('2026-10-20T14:00:01Z'), isTrue);
    expect(a >= b && a <= b, isTrue);
    expect(a.compareTo(b), 0);
  });
}
