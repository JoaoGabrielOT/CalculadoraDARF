import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/com_mod.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/modelos/meta.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

final _nomeMes = RegExp(r'^\d{4}-\d{2}\.json$');

Map<String, Object?> _regravado(String arquivo, Map<String, Object?> json) {
  if (arquivo == 'config.json') return Config.fromJson(json).toJson();
  if (_nomeMes.hasMatch(arquivo)) return Mes.fromJson(json).toJson();
  throw StateError('arquivo inesperado: $arquivo');
}

/// A ordem das chaves de cada objeto deve ser a que o Python grava
/// (`json.dumps` preserva a ordem de inserção).
void _conferirOrdem(Object? atual, Object? esperado, String caminho) {
  if (atual is Map && esperado is Map) {
    expect(
      atual.keys.toList(),
      esperado.keys.toList(),
      reason: 'ordem das chaves em $caminho',
    );
    for (final k in esperado.keys) {
      _conferirOrdem(atual[k], esperado[k], '$caminho.$k');
    }
  } else if (atual is List && esperado is List) {
    for (var i = 0; i < esperado.length; i++) {
      _conferirOrdem(atual[i], esperado[i], '$caminho[$i]');
    }
  }
}

Meta _metaMinima({bool? movel, List<Nivel>? niveis}) => Meta(
  id: 'meta-1',
  ticker: 'PETR4',
  loteId: 'a1',
  qtd: 10,
  criadaEm: '2026-10-28T12:00:00-03:00',
  movel: movel,
  niveis: niveis,
);

void main() {
  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('modelos'), startsWith('3.12'));
  });

  group('le arquivos gravados pelo Python 1.12 e preserva chaves '
      'desconhecidas', () {
    for (final caso in carregarCasos('modelos')) {
      test(caso.nome, () {
        final entrada = caso.entrada! as Map<String, Object?>;
        final saida = caso.saida! as Map<String, Object?>;
        expect(entrada.keys.toSet(), saida.keys.toSet());
        for (final arquivo in entrada.keys) {
          final atual = _regravado(
            arquivo,
            entrada[arquivo]! as Map<String, Object?>,
          );
          conferir(atual, saida[arquivo], caminho: arquivo);
          _conferirOrdem(atual, saida[arquivo], arquivo);
        }
      });
    }

    test('Config guarda chaves desconhecidas em extras e as regrava', () {
      final caso = carregarCasos('modelos')
          .firstWhere((c) => c.nome == 'config_pelo_python');
      final json =
          (caso.entrada! as Map<String, Object?>)['config.json']!
              as Map<String, Object?>;
      final config = Config.fromJson(json);
      expect(config.extras['noticias_notificar'], true);
      expect(config.extras['radar_ordem_lista'], ['PETR4', 'ITUB4', 'WEGE3']);
      expect(config.toJson()['noticias_notificar'], true);
      expect(config.toJson()['radar_ordem_lista'], ['PETR4', 'ITUB4', 'WEGE3']);
    });
  });

  group('leitura tolerante', () {
    test('qtd 100.0 vira 100; fracionária é recusada', () {
      final v = Venda.fromJson({
        'id': 'v',
        'data': '2026-05-10',
        'qtd': 100.0,
        'preco': 12,
      });
      expect(v.qtd, 100);
      expect(v.preco, 12.0);
      expect(v.mod, 0.0);
      expect(
        () => Venda.fromJson({
          'id': 'v',
          'data': '2026-05-10',
          'qtd': 100.5,
          'preco': 1,
        }),
        throwsFormatException,
      );
    });

    test('chaves ausentes assumem o padrão', () {
      final mes = Mes.fromJson({'mes': '2026-05'});
      expect(mes.fechado, false);
      expect(mes.darfAnterior, 0.0);
      expect(mes.lotes, isEmpty);
      expect(mes.excluidos, <String, double>{});
      expect(mes.resumo, isNull);
      expect(mes.toJson().containsKey('retroativo'), false);
      expect(mes.toJson().containsKey('resumo'), false);
      final config = Config.fromJson({});
      expect(config.tema, 'Dark');
      expect(config.caixa.data, '');
      expect(config.toJson()['caixa'], {'saldo': 0.0, 'data': '', 'mod': 0.0});
    });

    test('mesVazio devolve o mês de nucleo.py:121', () {
      expect(mesVazio('2026-10').toJson(), {
        'mes': '2026-10',
        'fechado': false,
        'darf_anterior': 0.0,
        'lotes': <Object?>[],
        'excluidos': <String, Object?>{},
        'mod': 0.0,
      });
    });
  });

  group('Meta', () {
    test('Meta.toJson omite campos ausentes e mantém movel false e niveis '
        'vazio', () {
      final minima = _metaMinima().toJson();
      for (final k in [
        'gatilho',
        'preco_alvo',
        'lucro_desejado',
        'stop_inicial',
        'stop_atual',
        'movel',
        'niveis',
        'oco',
        'execucao',
        'ultimo_erro',
        'cancelada_por',
        'cancelada_detalhe',
        'sugestao',
      ]) {
        expect(minima.containsKey(k), false, reason: k);
      }
      expect(minima['status'], 'ativa');
      expect(minima['tipo'], '');
      expect(minima['mod'], 0.0);

      final presentes = _metaMinima(movel: false, niveis: []).toJson();
      expect(presentes['movel'], false);
      expect(presentes['niveis'], <Object?>[]);
    });

    test('copiar é independente do original', () {
      final original = Meta.fromJson({
        'id': 'm',
        'ticker': 'VALE3',
        'tipo': 'Ação',
        'lote_id': 'a',
        'qtd': 5,
        'gatilho': 'stop',
        'stop_inicial': 10.0,
        'movel': true,
        'stop_atual': 10.0,
        'niveis': [
          {'desde': '2026-10-01', 'stop': 10.0, 'calc_em': '2026-10-01'},
        ],
        'criada_em': '2026-10-01T10:00:00-03:00',
        'status': 'ativa',
        'sugestao': {
          'stop': 10.0,
          'lista': [1],
        },
        'mod': 3,
        'campo_novo': {'x': 1},
      });
      final copia = original.copiar();
      expect(copia.toJson(), original.toJson());
      copia.niveis!.add(Nivel(desde: 'x', stop: 1, calcEm: 'y'));
      copia.niveis![0].stop = 99;
      (copia.sugestao!['lista']! as List<Object?>).add(2);
      (copia.extras['campo_novo']! as Map<String, Object?>)['y'] = 2;
      copia.status = 'cancelada';
      expect(original.niveis, hasLength(1));
      expect(original.niveis![0].stop, 10.0);
      expect(original.sugestao!['lista'], [1]);
      expect(original.extras['campo_novo'], {'x': 1});
      expect(original.status, 'ativa');
    });
  });

  group('mesmosCampos', () {
    test('ignora mod, vendas e os campos pedidos', () {
      final a = {'id': 'x', 'qtd': 1, 'mod': 5.0, 'vendas': <Object?>[]};
      final b = {
        'id': 'x',
        'qtd': 1.0,
        'mod': 9.0,
        'vendas': [1],
      };
      expect(mesmosCampos(a, b), true);
      expect(mesmosCampos({...a, 'qtd': 2}, b), false);
      expect(mesmosCampos({...a, 'niveis': 1}, {...b, 'niveis': 2}), false);
      expect(
        mesmosCampos(
          {...a, 'niveis': 1},
          {...b, 'niveis': 2},
          ignorar: {'niveis'},
        ),
        true,
      );
      expect(
        mesmosCampos(
          {
            'a': [1, 2],
          },
          {
            'a': [1, 2],
          },
        ),
        true,
      );
    });

    test('ComMod é implementado pelos modelos com carimbo', () {
      final List<ComMod> todos = [
        Venda(id: 'v', data: '2026-01-01', qtd: 1, preco: 1, mod: 2),
        Amigo(email: 'a@b.c', desde: '2026-01-01', mod: 3),
        Caixa(mod: 4),
        _metaMinima(),
      ];
      expect(todos.map((m) => m.mod), [2.0, 3.0, 4.0, 0.0]);
    });
  });

  group('constantes e erros', () {
    test('valores de nucleo.py:16-24', () {
      expect(taxaB3Swing, 0.0003);
      expect(taxaB3Daytrade, 0.00023);
      expect(corretagemPorOrdem, 0.0);
      expect(aliqSwing, 0.15);
      expect(aliqDaytrade, 0.20);
      expect(irrfSwing, 0.00005);
      expect(irrfDaytrade, 0.01);
      expect(limiteIsencao, 20000.0);
      expect(darfMinimo, 10.0);
      expect(diasLiquidacao, 2);
      expect(sufixosBdr, ['31', '32', '33', '34', '35', '39']);
    });

    test('toString devolve a mensagem', () {
      expect(
        ErroValidacao('Quantidade inválida.').toString(),
        'Quantidade inválida.',
      );
      expect(SemDados('x').toString(), 'x');
      expect(LimiteConsultas('y').toString(), 'y');
      expect(ErroConexao('z').toString(), 'z');
      expect(SemSugestao('w').toString(), 'w');
      expect(ErroValidacao('a'), isA<Exception>());
    });
  });

  group('Ambiente', () {
    test('Ambiente.fixo devolve ids sequenciais e relógio fixo', () {
      final a = Ambiente.fixo();
      expect(a.novoId(), 'id0001');
      expect(a.novoId(), 'id0002');
      expect(a.agora(), 1761000000.123);
      expect(a.agora(), 1761000000.123);
      expect(a.hoje(), '2026-10-28');
      expect(a.agoraBr().iso(), '2026-10-28T12:00:00-03:00');
      expect(a.agoraBr().desvio, fusoBrasilia);
      expect(Ambiente.fixo().novoId(), 'id0001');
      final b = Ambiente.fixo(
        agora: 5.5,
        hoje: '2026-01-02',
        agoraBr: '2026-01-02T08:30:00-03:00',
      );
      expect(b.agora(), 5.5);
      expect(b.hoje(), '2026-01-02');
      expect(b.agoraBr().iso(), '2026-01-02T08:30:00-03:00');
    });

    test('Ambiente.sistema usa relógio real, ids de 32 hex e Brasília', () {
      final a = Ambiente.sistema();
      final antes = DateTime.now().millisecondsSinceEpoch / 1000;
      final t = a.agora();
      expect(t, greaterThanOrEqualTo(antes - 1));
      expect(t, lessThan(antes + 5));
      expect((t * 1000) == (t * 1000).truncateToDouble(), true);
      final id = a.novoId();
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), true);
      expect(a.novoId(), isNot(id));
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(a.hoje()), true);
      expect(a.agoraBr().desvio, fusoBrasilia);
    });

    test('ambiente global é substituível', () {
      final original = ambiente;
      addTearDown(() => ambiente = original);
      ambiente = Ambiente.fixo();
      expect(ambiente.novoId(), 'id0001');
    });
  });

  test('modelos de barras guardam os campos do mercado', () {
    final dt = DataHora.deTimestamp(1761674400, fusoBrasilia);
    final b = Barra(ts: 1761674400, dt: dt, alta: 40.5);
    expect(b.baixa, isNull);
    expect(b.abre, isNull);
    final d = BarraDiaria(data: '2026-10-28', alta: 2, baixa: 1, fech: 1.5);
    expect(d.abre, isNull);
    final h = HistoricoIntradiario(
      barras: [b],
      fonte: 'Yahoo Finance',
      intervalo: '5m',
      diarias: Diarias(barras: [d], hoje: '2026-10-28', preco: 1.5),
    );
    expect(h.diarias!.barras.single.fech, 1.5);
    expect(h.diarias!.fonte, isNull);
  });
}
