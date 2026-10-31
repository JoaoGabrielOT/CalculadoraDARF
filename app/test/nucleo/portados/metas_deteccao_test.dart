// Porte dos testes de detecção do gatilho e de stop móvel de
// tests/test_metas.py (TestDeteccao, TestStop, TestStopMovel,
// TestRevisaoStopMovel, TestRevisaoMesclagem).

import 'package:calculadoradarf/nucleo/compat/numeros.dart';
import 'package:calculadoradarf/nucleo/compat/ordenacao.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/metas/criacao.dart';
import 'package:calculadoradarf/nucleo/metas/deteccao.dart';
import 'package:calculadoradarf/nucleo/metas/preco_alvo.dart';
import 'package:calculadoradarf/nucleo/mercado/indicadores.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/base_metas.dart';
import '../apoio/referencias.dart';

/// `TestStopMovel.barras`: [n] pregões consecutivos terminando em [fim].
List<BarraDiaria> _barras({
  int n = 30,
  String fim = '2026-10-22',
  double alta = 11.0,
  double baixa = 9.0,
  double fech = 10.0,
}) => [
  for (var i = 0; i < n; i++)
    dia(somarDias(fim, -(n - 1 - i)), alta, baixa, fech),
];

/// `TestRevisaoStopMovel.barras_aleatorias`: o Dart não reproduz o
/// `random.Random(7)` do Python, então as barras vêm do JSON de referência.
List<BarraDiaria> _barrasAleatorias(int n) {
  final caso = carregarCasos('metas_deteccao').firstWhere(
    (c) => c.funcao == 'barras_aleatorias' && (c.entrada! as Map)['n'] == n,
  );
  final barras =
      (caso.saida! as Map<String, Object?>)['barras']! as List<Object?>;
  return [
    for (final b in barras.cast<Map<String, Object?>>())
      BarraDiaria(
        data: b['data']! as String,
        abre: (b['abre']! as num).toDouble(),
        alta: (b['alta']! as num).toDouble(),
        baixa: (b['baixa']! as num).toDouble(),
        fech: (b['fech']! as num).toDouble(),
      ),
  ];
}

List<Map<String, Object?>> _json(Meta m) => [
  for (final n in m.niveis!) n.toJson(),
];

void main() {
  final base = BaseMetas();
  setUp(base.preparar);

  Meta movel([double preco = 5.0]) => criarStop(
    base.repo,
    base.cfg,
    'L1',
    100,
    preco,
    movel: true,
    agora: base.criada,
  );

  group('TestDeteccao', () {
    test('TestDeteccao.test_achar_barra', () {
      final barras = [
        barra('2026-10-20T10:00:00', 25),
        barra('2026-10-20T11:00:00', 21.0),
        barra('2026-10-20T12:00:00', 21.78),
        barra('2026-10-20T13:00:00', 30),
      ];
      final b = acharBarra(barras, 21.78, base.criada);
      // igual ao alvo conta; 10:00 é anterior à criação
      expect(b!.dt, dt('2026-10-20T12:00:00'));
    });

    test('TestDeteccao.test_barra_anterior_ignorada', () {
      expect(
        acharBarra([barra('2026-10-20T10:59:00', 99)], 21.78, base.criada),
        isNull,
      );
    });

    test('TestDeteccao.test_barra_na_hora_da_criacao_vale', () {
      expect(
        acharBarra([barra('2026-10-20T11:00:00', 22)], 21.78, base.criada),
        isNotNull,
      );
    });

    test('TestDeteccao.test_sem_barra_atingindo', () {
      expect(
        acharBarra([barra('2026-10-21T10:00:00', 21.77)], 21.78, base.criada),
        isNull,
      );
    });
  });

  test('TestStop.test_dispara_com_minima_igual_ao_stop', () {
    final niveis = [
      Nivel(desde: '2026-10-20', stop: 9.0, calcEm: '2026-10-20'),
    ];
    final b = acharBarraStop(
      [
        barraS('2026-10-21T10:00:00', 10, 9.01),
        barraS('2026-10-21T11:00:00', 10, 9.00),
      ],
      niveis,
      base.criada,
    );
    expect(b!.$1.dt, dt('2026-10-21T11:00:00'));
    expect(
      acharBarraStop(
        [barraS('2026-10-21T10:00:00', 10, 9.01)],
        niveis,
        base.criada,
      ),
      isNull,
    );
    expect(
      acharBarraStop(
        [barraS('2026-10-20T10:00:00', 10, 1)],
        niveis,
        base.criada,
      ),
      isNull,
    );
  });

  group('TestStopMovel', () {
    test(
      'TestStopMovel.test_subida_acrescenta_nivel_a_partir_do_dia_seguinte',
      () {
        final m = movel(4.0);
        final subiu = atualizarStopMovel(m, _barras(), '2026-10-25');
        expect(subiu, isTrue);
        expect(m.stopAtual, 5.0); // 11 - 3*2
        final novo = m.niveis![1];
        expect(
          (novo.desde, novo.calcEm, novo.stop),
          ('2026-10-21', '2026-10-20', 5.0),
        );
      },
    );

    test('TestStopMovel.test_idempotente_e_nunca_desce', () {
      final m = movel(4.0);
      const hoje = '2026-10-25';
      atualizarStopMovel(m, _barras(), hoje);
      final antes = _json(m);
      expect(atualizarStopMovel(m, _barras(), hoje), isFalse);
      expect(_json(m), antes);
      // volatilidade maior derrubaria o Chandelier: o stop continua onde estava
      final piores = _barras(baixa: 1.0);
      expect(atualizarStopMovel(m, piores, hoje), isFalse);
      expect(m.stopAtual, 5.0);
    });

    test('TestStopMovel.test_stop_acima_do_chandelier_nao_muda', () {
      final m = movel(7.0);
      expect(atualizarStopMovel(m, _barras(), '2026-10-25'), isFalse);
      expect(m.niveis!.length, 1);
    });

    test('TestStopMovel.test_so_pregoes_fechados_e_desde_a_criacao', () {
      final m = movel(4.0);
      // hoje = 20/10 (dia da criação): ainda não há pregão fechado a partir da criação
      expect(atualizarStopMovel(m, _barras(), '2026-10-20'), isFalse);
      expect(m.stopAtual, 4.0);
    });

    test('TestStopMovel.test_nivel_com_desde_posterior_nao_vale', () {
      final niveis = [
        Nivel(desde: '2026-10-20', stop: 5.0, calcEm: 'x'),
        Nivel(desde: '2026-10-22', stop: 9.0, calcEm: 'x'),
      ];
      expect(
        acharBarraStop(
          [barraS('2026-10-21T10:00:00', 10, 8.0)],
          niveis,
          base.criada,
        ),
        isNull,
      );
      expect(
        acharBarraStop(
          [barraS('2026-10-22T10:00:00', 10, 8.0)],
          niveis,
          base.criada,
        ),
        isNotNull,
      );
    });
  });

  group('TestRevisaoStopMovel', () {
    /// `referencia`: algoritmo anterior, recalcula o Chandelier de todo o
    /// prefixo a cada pregão.
    void referencia(Meta meta, List<BarraDiaria> barras, String hoje) {
      final criada = DataHora.parse(meta.criadaEm).data;
      final fechadas = ordenadoPor(
        barras.where((b) => b.data.compareTo(hoje) < 0),
        (b) => [b.data],
      );
      final niveis = meta.niveis ??= [];
      var ultimo = maxDe([for (final n in niveis) n.stop, meta.stopAtual!]);
      for (final (i, b) in fechadas.indexed) {
        if (b.data.compareTo(criada) < 0) continue;
        final c = calcularChandelier(fechadas.sublist(0, i + 1));
        if (c == null) continue;
        final novo = pisoCentavo(c);
        if (novo > ultimo + 1e-9) {
          niveis.add(
            Nivel(desde: somarDias(b.data, 1), stop: novo, calcEm: b.data),
          );
          ultimo = novo;
        }
      }
      meta.stopAtual = ultimo;
    }

    test('TestRevisaoStopMovel.test_passada_incremental_equivale_ao_recalculo_completo', () {
      final barras = _barrasAleatorias(120);
      for (final (inicio, hoje) in [
        (3.0, '2026-09-20'),
        (8.0, '2026-09-29'),
        (1.0, '2026-10-01'),
      ]) {
        final a = criarStop(
          base.repo,
          base.cfg,
          'L1',
          100,
          inicio,
          movel: true,
          agora: dt('2026-06-05T11:00:00'),
        );
        final b = a.copiar();
        base.cfg.metas.clear();
        atualizarStopMovel(a, barras, hoje);
        referencia(b, barras, hoje);
        expect(_json(a), _json(b));
        expect(a.stopAtual, b.stopAtual);
        expect(a.niveis!.length, greaterThan(1));
      }
    });

    test(
      'TestRevisaoStopMovel.test_serie_chandelier_igual_ao_calculo_por_prefixo',
      () {
        final barras = _barrasAleatorias(60);
        final serie = serieChandelier(barras);
        expect(serie.length, barras.length);
        for (final (i, valor) in serie.indexed) {
          expect(valor, calcularChandelier(barras.sublist(0, i + 1)));
        }
      },
    );

    test('TestRevisaoStopMovel.test_nao_recalcula_o_atr_a_cada_pregao', () {
      final m = criarStop(
        base.repo,
        base.cfg,
        'L1',
        100,
        1.0,
        movel: true,
        agora: dt('2026-06-05T11:00:00'),
      );
      var chamadas = 0;
      List<double?> contadora(List<BarraDiaria> b) {
        chamadas++;
        return serieChandelier(b);
      }

      atualizarStopMovel(
        m,
        _barrasAleatorias(120),
        '2026-10-01',
        serie: contadora,
      );
      expect(chamadas, 1);
    });
  });

  test('TestRevisaoMesclagem.test_subida_do_stop_movel_nao_carimba_mod', () {
    final m = movel(4.0);
    m.mod = 1.0;
    base.repo.gravarConfig(base.cfg, carimbar: false);
    final barras = [
      for (var i = 0; i < 30; i++)
        dia(somarDias('2026-10-22', -(29 - i)), 11.0, 9.0, 10.0),
    ];
    expect(atualizarStopMovel(m, barras, '2026-10-25'), isTrue);
    base.repo.gravarConfig(base.cfg);
    final gravada = base.repo.lerConfig().metas[0];
    expect(gravada.stopAtual, 5.0);
    expect(gravada.mod, 1.0);
    expect(gravada.status, 'ativa');
    m.status = 'cancelada'; // outra mudança continua carimbando
    base.repo.gravarConfig(base.cfg);
    expect(base.repo.lerConfig().metas[0].mod, greaterThan(1.0));
  });
}
