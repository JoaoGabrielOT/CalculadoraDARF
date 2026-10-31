import 'dart:math';

import 'compat/numeros.dart';
import 'datas.dart';

/// Relógio, ids e "hoje" injetáveis; os testes trocam [ambiente] por
/// [Ambiente.fixo] (mesmos valores congelados do gerador de referências).
class Ambiente {
  Ambiente({
    required this.agora,
    required this.novoId,
    required this.hoje,
    required this.agoraBr,
  });

  /// Relógio e ids reais.
  factory Ambiente.sistema() {
    final aleatorio = Random.secure();
    // nucleo.py:39-40
    double agora() =>
        arredondar(DateTime.now().microsecondsSinceEpoch / 1000000, 3);
    return Ambiente(
      agora: agora,
      // uuid4().hex
      novoId: () => [
        for (var i = 0; i < 16; i++)
          aleatorio.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join(),
      hoje: () => isoDeDateTime(DateTime.now()),
      agoraBr: () => DataHora.deTimestamp(agora(), fusoBrasilia),
    );
  }

  /// Valores congelados; os ids são `id0001`, `id0002`... por instância.
  factory Ambiente.fixo({
    double agora = 1761000000.123,
    String hoje = '2026-10-28',
    String? agoraBr,
  }) {
    var contador = 0;
    final instante = DataHora.parse(agoraBr ?? '2026-10-28T12:00:00-03:00');
    return Ambiente(
      agora: () => agora,
      novoId: () => 'id${(++contador).toString().padLeft(4, '0')}',
      hoje: () => hoje,
      agoraBr: () => instante,
    );
  }

  /// Segundos desde a época, com 3 casas.
  final double Function() agora;

  /// Id único (`uuid4().hex`).
  final String Function() novoId;

  /// Data local `AAAA-MM-DD`.
  final String Function() hoje;

  /// Agora no fuso de Brasília (−03:00).
  final DataHora Function() agoraBr;
}

Ambiente ambiente = Ambiente.sistema();
