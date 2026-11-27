import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/nucleo/relatorios/relatorio.dart';

const caminhoFixtureRelatorio =
    '../tests/fixtures/relatorio-abertura-2026-11-26.json';

/// Fixture real, lida e decodificada a cada chamada (cópia nova).
Map<String, Object?> fixtureRelatorio() =>
    (jsonDecode(File(caminhoFixtureRelatorio).readAsStringSync()) as Map)
        .cast<String, Object?>();

/// A fixture com [n] cópias do primeiro ativo (posições `0..n-1`, tickers
/// `ATV0`, `ATV1`…) e o termômetro recontado pelas cópias.
Map<String, Object?> fixtureComAtivos(int n) {
  final f = fixtureRelatorio();
  final primeiro = (f['ativos'] as List).first as Map;
  f['ativos'] = [
    for (var i = 0; i < n; i++)
      {...primeiro.cast<String, Object?>(), 'posicao': i, 'ticker': 'ATV$i'},
  ];
  final cont = {for (final l in Leitura.values) l.name: 0};
  cont[leituraDe(primeiro['leitura']).name] = n;
  f['termometro'] = cont;
  return f;
}

const caminhoFixtureRelatorio27 =
    '../tests/fixtures/relatorio-abertura-2026-11-27.json';

/// A fixture de 27/11 (com consenso, placar, classificação e potencial).
Map<String, Object?> fixtureRelatorio27() =>
    (jsonDecode(File(caminhoFixtureRelatorio27).readAsStringSync()) as Map)
        .cast<String, Object?>();

const caminhoFixtureRelatorioGuia =
    '../tests/fixtures/relatorio-abertura-2026-11-27-guia.json';

/// A fixture de 27/11 com os campos do guia (preço × alvo, motivo, frase).
Map<String, Object?> fixtureRelatorioGuia() =>
    (jsonDecode(File(caminhoFixtureRelatorioGuia).readAsStringSync()) as Map)
        .cast<String, Object?>();
