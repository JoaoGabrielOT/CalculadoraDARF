import 'dart:convert';

import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/armazenamento.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/fechamento.dart';
import 'package:calculadoradarf/nucleo/metas/verificacao.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:calculadoradarf/nucleo/repositorio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

/// Executa uma operação do roteiro; devolve o retorno como JSON.
Object? _executar(Repositorio repo, Map<String, Object?> op) {
  try {
    switch (op['op']) {
      case 'fechar_mes':
        final (r, prox) = fecharMes(repo, repo.carregar(op['mes']! as String));
        return {'apuracao': r.toJson(), 'prox': prox};
      case 'mes_aceita':
        return mesAceitaVendaRetroativa(
          repo,
          op['mes']! as String,
          op['mes_atual']! as String,
        );
      case 'registrar_retroativa':
        final v = _mapa(op['venda']);
        return registrarVendaRetroativa(
          repo,
          repo.carregar(op['mes']! as String),
          op['lote_id']! as String,
          (
            data: v['data']! as String,
            qtd: (v['qtd']! as num).toInt(),
            preco: (v['preco']! as num).toDouble(),
          ),
        );
      case 'corrigir_tipos':
        return corrigirTipos(repo);
      case 'historico':
        final (freq, tipos) = historicoTickers(
          repo,
          mesesRecentes: (op['meses_recentes']! as num).toInt(),
        );
        return {'freq': freq, 'tipos': tipos};
      case 'sugestoes':
        final (lista, tipos) = sugestoesTickers(
          repo,
          repo.carregar(op['mes']! as String),
          soCustodia: op['so_custodia']! as bool,
        );
        return {'lista': lista, 'tipos': tipos};
      case 'custodia_atual':
        return custodiaAtual(repo).toList()..sort();
    }
  } on ErroValidacao catch (e) {
    return {'erro': e.mensagem};
  }
  throw StateError('operação desconhecida: ${op['op']}');
}

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('fechamento'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('fechamento')) {
    test('roteiro: ${caso.nome}', () {
      final entrada = _mapa(caso.entrada);
      final memoria = ArmazenamentoMemoria();
      for (final e in _mapa(entrada['arquivos']).entries) {
        memoria.gravar(e.key, jsonEncode(e.value));
      }
      final repo = Repositorio(memoria);
      final fixo = Ambiente.fixo();
      var agora = 0.0;
      // ids contínuos no roteiro; só o relógio muda entre as operações
      ambiente = Ambiente(
        agora: () => agora,
        novoId: fixo.novoId,
        hoje: fixo.hoje,
        agoraBr: fixo.agoraBr,
      );
      final esperados = _mapa(caso.saida)['resultados']! as List<Object?>;
      final operacoes = entrada['operacoes']! as List<Object?>;
      for (final (i, bruta) in operacoes.indexed) {
        final op = _mapa(bruta);
        agora = (op['agora']! as num).toDouble();
        final esperado = _mapa(esperados[i]);
        final caminho = '\$.resultados[$i]';
        conferir(
          _executar(repo, op),
          esperado['retorno'],
          caminho: '$caminho.retorno',
        );
        final arquivos = _mapa(esperado['arquivos']);
        expect(
          memoria.listar().toSet(),
          arquivos.keys.toSet(),
          reason: '$caminho: arquivos',
        );
        for (final a in arquivos.entries) {
          conferir(
            jsonDecode(memoria.ler(a.key)!),
            a.value,
            caminho: '$caminho.${a.key}',
          );
        }
      }
    });
  }

  group('custo médio', () {
    late Repositorio repo;

    setUp(() {
      ambiente = Ambiente.fixo();
      repo = Repositorio(ArmazenamentoMemoria());
    });

    Lote lote(
      String id,
      String data,
      int qtd,
      double preco, {
      String? origem,
      List<Venda>? vendas,
    }) => Lote(
      id: id,
      origem: origem,
      ticker: 'PETR4',
      tipo: 'Ação',
      dataCompra: data,
      qtd: qtd,
      preco: preco,
      vendas: vendas,
    );

    Mes marcado(
      String mes,
      List<Lote> lotes,
      (int, double)? petr4, {
      double comum = 0,
      double dayTrade = 0,
      bool fechado = false,
    }) => Mes(
      mes: mes,
      fechado: fechado,
      lotes: lotes,
      metodo: metodoCustoMedio,
      posicaoInicial: {
        if (petr4 != null)
          'PETR4': PosicaoFiscal(qtd: petr4.$1, custo: petr4.$2),
      },
      prejuizoAnterior: PrejuizoAcumulado(comum: comum, dayTrade: dayTrade),
    );

    /// 03/2026: 100 levadas a R$ 1.000,00; compra X de 100 a 11,00 em 05/03
    /// e venda de 50 de P0 a 10,00 em 20/03.
    Mes marco() => marcado(
      '2026-03',
      [
        lote(
          'P0',
          '2026-02-10',
          100,
          10,
          origem: 'P',
          vendas: [Venda(id: 'V1', data: '2026-03-20', qtd: 50, preco: 10)],
        ),
        lote('X', '2026-03-05', 100, 11),
      ],
      (100, 1000.00),
      comum: 10,
      dayTrade: 5,
    );

    test('fechamento leva posição e prejuízo', () {
      // compra: 1000,00 + arredondar(100 × 11 × 1,0003) = 1000 + 1100,33
      //   = 2100,33 (200)
      // venda: baixa arredondar(50 × 2100,33 / 200) = 525,08 → 1575,25 (150)
      //   resultado 500 − 525,08 − 50 × 10 × 0,0003 = −25,23
      // isento: prejuízo comum 10 + 25,23 = 35,23; day trade 5 intacto
      repo.salvar(marco());
      final (r, prox) = fecharMes(repo, repo.carregar('2026-03'));
      expect(prox, '2026-04');
      final abril = repo.carregar('2026-04');
      expect(abril.metodo, metodoCustoMedio);
      expect(abril.posicaoInicial!.keys, ['PETR4']);
      expect(abril.posicaoInicial!['PETR4']!.qtd, 150);
      expect(abril.posicaoInicial!['PETR4']!.custo, closeTo(1575.25, 1e-9));
      expect(abril.prejuizoAnterior!.comum, closeTo(35.23, 1e-9));
      expect(abril.prejuizoAnterior!.dayTrade, 5.0);
      // as cópias levadas somam a posição fiscal
      expect(abril.lotes.map((l) => (l.origem, l.qtd)), [
        ('P0', 50),
        ('X', 100),
      ]);
      expect(apurar(abril).inconsistentes, isEmpty);
      expect(
        mensagemFechamento(r, prox),
        'Não há DARF a pagar neste mês.\n\n'
        'Prejuízo levado para o próximo mês: comum R\$ 35,23; '
        'day trade R\$ 5,00\n\n'
        'Ativos não vendidos foram levados para 04/2026.',
      );
    });

    test('sem prejuízo, a mensagem não ganha a linha', () {
      repo.salvar(
        marcado(
          '2026-03',
          [lote('P0', '2026-02-10', 100, 10, origem: 'P')],
          (100, 1000.0),
        ),
      );
      final (r, prox) = fecharMes(repo, repo.carregar('2026-03'));
      expect(
        mensagemFechamento(r, prox),
        'Não há DARF a pagar neste mês.\n\n'
        'Ativos não vendidos foram levados para 04/2026.',
      );
    });

    test('mês seguinte fechado não é alterado', () {
      repo.salvar(marco());
      repo.salvar(Mes(mes: '2026-04', fechado: true));
      final antes = jsonEncode(repo.carregar('2026-04').toJson());
      fecharMes(repo, repo.carregar('2026-03'));
      expect(jsonEncode(repo.carregar('2026-04').toJson()), antes);
      expect(repo.carregar('2026-03').fechado, isTrue);
    });

    test('inconsistência bloqueia o fechamento sem gravar', () {
      // posição inicial de 100, mas a cópia levada só tem 80
      repo.salvar(
        marcado(
          '2026-03',
          [lote('P0', '2026-02-10', 80, 10, origem: 'P')],
          (100, 1000.0),
        ),
      );
      expect(
        () => fecharMes(repo, repo.carregar('2026-03')),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'O mês não pode ser fechado com saldo inconsistente.\n\n'
                'Saldo inconsistente em PETR4: confira as vendas',
          ),
        ),
      );
      expect(repo.carregar('2026-03').fechado, isFalse);
      expect(repo.existeMes('2026-04'), isFalse);
    });

    test(
      'prepararFechamento recusa saldo inconsistente sem consultar',
      () async {
        repo.salvar(
          marcado(
            '2026-03',
            [lote('P0', '2026-02-10', 80, 10, origem: 'P')],
            (100, 1000.0),
          ),
        );
        final preparo = await prepararFechamento(
          repo,
          Config(),
          '2026-03',
          (t, d) => throw StateError('não deveria consultar'),
        );
        expect(
          preparo.bloqueio,
          'O mês não pode ser fechado com saldo inconsistente.\n\n'
          'Saldo inconsistente em PETR4: confira as vendas',
        );
      },
    );

    test('retroativa antes do corte baixa a posição inicial', () {
      // baixa arredondar(30 × 1000,30 / 100) = 300,09 → 700,21 (70)
      repo.salvar(
        marcado(
          '2026-03',
          [lote('P0', '2026-01-15', 100, 10, origem: 'P')],
          (100, 1000.30),
        ),
      );
      expect(mesAceitaVendaRetroativa(repo, '2026-02', '2026-03'), isTrue);
      final d = repo.carregar('2026-03');
      expect(
        registrarVendaRetroativa(repo, d, 'P0', (
          data: '2026-02-10',
          qtd: 30,
          preco: 12,
        )),
        '2026-02',
      );
      final marco = repo.carregar('2026-03');
      expect(marco.lotes.single.qtd, 70);
      expect(marco.posicaoInicial!['PETR4']!.qtd, 70);
      expect(marco.posicaoInicial!['PETR4']!.custo, closeTo(700.21, 1e-9));
      expect(apurar(marco).inconsistentes, isEmpty);
      // o mês da venda continua pelo método por compra
      expect(repo.carregar('2026-02').metodo, isNull);
    });

    test('retroativa de toda a posição tira o ticker', () {
      repo.salvar(
        marcado(
          '2026-03',
          [lote('P0', '2026-01-15', 100, 10, origem: 'P')],
          (100, 1000.30),
        ),
      );
      registrarVendaRetroativa(repo, repo.carregar('2026-03'), 'P0', (
        data: '2026-02-10',
        qtd: 100,
        preco: 12,
      ));
      final marco = repo.carregar('2026-03');
      expect(marco.lotes, isEmpty);
      expect(marco.posicaoInicial, isEmpty);
    });

    test('retroativa sem posição inicial é recusada sem gravar', () {
      repo.salvar(
        marcado('2026-03', [
          lote('P0', '2026-01-15', 100, 10, origem: 'P'),
        ], null),
      );
      final antes = jsonEncode(repo.carregar('2026-03').toJson());
      expect(
        () => registrarVendaRetroativa(repo, repo.carregar('2026-03'), 'P0', (
          data: '2026-02-10',
          qtd: 30,
          preco: 12,
        )),
        throwsA(
          isA<ErroValidacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Não há posição de PETR4 no início de 03/2026 para essa venda.',
          ),
        ),
      );
      expect(jsonEncode(repo.carregar('2026-03').toJson()), antes);
      expect(repo.existeMes('2026-02'), isFalse);
    });

    test('retroativa a partir do corte é recusada', () {
      repo.salvar(marcado('2026-03', [], null, fechado: true));
      repo.salvar(
        marcado(
          '2026-04',
          [lote('P0', '2026-02-10', 100, 10, origem: 'P')],
          (100, 1000.0),
        ),
      );
      expect(mesAceitaVendaRetroativa(repo, '2026-03', '2026-04'), isFalse);
      expect(mesPorCustoMedio(repo, '2026-03'), isTrue);
      expect(mesPorCustoMedio(repo, '2026-02'), isFalse);
      expect(
        textoRetroativaCustoMedio,
        'Meses apurados por custo médio não aceitam venda retroativa.',
      );
    });

    group('edição', () {
      Lote novo(Lote l, {int? qtd, double? preco, String? data}) => Lote(
        id: l.id,
        origem: l.origem,
        ticker: l.ticker,
        tipo: l.tipo,
        dataCompra: data ?? l.dataCompra,
        qtd: qtd ?? l.qtd,
        preco: preco ?? l.preco,
        vendas: l.vendas,
      );

      test('cópia levada não edita qtd nem preço', () {
        final d = marco();
        final p0 = d.lotes.first;
        const msg =
            'Compra levada de um mês anterior: quantidade e preço fazem '
            'parte da posição inicial e não podem ser editados.';
        expect(erroEdicaoLote(p0, novo(p0, qtd: 120), mes: d), msg);
        expect(erroEdicaoLote(p0, novo(p0, preco: 9.5), mes: d), msg);
        expect(erroEdicaoLote(p0, novo(p0), mes: d), isNull);
        // no método por compra continua editável
        expect(erroEdicaoLote(p0, novo(p0, qtd: 120)), isNull);
        expect(
          erroEdicaoLote(p0, novo(p0, qtd: 120), mes: Mes(mes: '2026-03')),
          isNull,
        );
      });

      test('compra nova do mês continua editável', () {
        final d = marco();
        final x = d.lotes.last;
        expect(
          erroEdicaoLote(
            x,
            novo(x, qtd: 120, preco: 10.5, data: '2026-03-01'),
            mes: d,
          ),
          isNull,
        );
      });

      test('compra com data anterior ao mês é recusada', () {
        final d = marco();
        final x = d.lotes.last;
        const msg =
            'Em meses pelo custo médio, a compra precisa ter data dentro do '
            'mês, a partir de 01/03/2026.';
        expect(erroEdicaoLote(x, novo(x, data: '2026-02-28'), mes: d), msg);
        expect(erroCompraForaDoMes(d, '2026-02-28'), msg);
        expect(erroCompraForaDoMes(d, '2026-03-01'), isNull);
        expect(erroCompraForaDoMes(Mes(mes: '2026-03'), '2026-02-28'), isNull);
      });
    });
  });
}
