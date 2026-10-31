import 'package:calculadoradarf/nucleo/apuracao.dart';
import 'package:calculadoradarf/nucleo/constantes.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/modelos/lote.dart';
import 'package:calculadoradarf/nucleo/modelos/mes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;

Lote _lote(Object? json) => Lote.fromJson(_mapa(json));

double _num(Object? v) => (v! as num).toDouble();

void main() {
  tearDown(() => corretagemPorOrdem = 0.0);

  test('referências geradas com Python 3.12', () {
    expect(versaoPythonDasReferencias('apuracao'), startsWith('3.12'));
  });

  for (final caso in carregarCasos('apuracao')) {
    test('${caso.funcao}: ${caso.nome}', () {
      final e = _mapa(caso.entrada);
      switch (caso.funcao) {
        case 'apurar':
          corretagemPorOrdem = _num(e['corretagem']);
          final d = Mes.fromJson(_mapa(e['mes']));
          final r = apurar(d);
          final saida = _mapa(caso.saida);
          conferir(r.toJson(), saida['apuracao'], caminho: r'$.apuracao');
          conferir(infoDarf(r, d.mes), saida['info_darf']);
          conferir(
            mensagemFechamento(r, proximoMes(d.mes)),
            saida['mensagem_fechamento'],
          );
        case 'calcular_venda':
          corretagemPorOrdem = _num(e['corretagem']);
          final r = calcularVendaQtd(
            _lote(e['lote']),
            e['qtd']! as num,
            _num(e['preco']),
            e['data']! as String,
          );
          conferir(r.toJson(), caso.saida);
        case 'regras':
          final l = _lote(e['lote']);
          final s = _mapa(caso.saida);
          conferir(vendido(l), s['vendido']);
          conferir(restante(l), s['restante']);
          conferir(statusLote(l), s['status']);
          conferir(
            semVenda(l, e['venda_id']! as String).toJson(),
            s['sem_venda'],
          );
        case 'erro_edicao_lote':
          conferir(
            erroEdicaoLote(_lote(e['lote']), _lote(e['novo'])),
            caso.saida,
          );
        case 'tipo_por_ticker':
          conferir(tipoPorTicker(e['ticker'] as String?), caso.saida);
        case 'corrigir_tipos_mes':
          final d = Mes.fromJson(_mapa(e['mes']));
          final s = _mapa(caso.saida);
          conferir(corrigirTiposMes(d), s['mudou']);
          conferir(d.toJson(), s['mes']);
        case 'resultado_aberto':
          final r = resultadoAberto(
            _lote(e['lote']),
            (e['preco_atual'] as num?)?.toDouble(),
          );
          final esperado = caso.saida as List<Object?>?;
          if (esperado == null) {
            expect(r, isNull);
          } else {
            conferir([r!.$1, r.$2], esperado);
          }
        default:
          fail('função desconhecida: ${caso.funcao}');
      }
    });
  }

  test('prejuízo de um mês não abate o mês seguinte', () {
    // nucleo.py:307-367: a compensação só vale dentro do mês; a 1.12 não
    // leva prejuízo de um mês para o seguinte.
    final prejuizo = Mes(
      mes: '2026-03',
      lotes: [
        Lote(
          id: 'l1',
          ticker: 'AAPL34',
          tipo: 'BDR',
          dataCompra: '2026-03-02',
          qtd: 100,
          preco: 50.0,
          vendas: [Venda(id: 'v1', data: '2026-03-10', qtd: 100, preco: 40.0)],
        ),
      ],
    );
    final lucro = Mes(
      mes: '2026-04',
      lotes: [
        Lote(
          id: 'l2',
          ticker: 'AAPL34',
          tipo: 'BDR',
          dataCompra: '2026-04-02',
          qtd: 100,
          preco: 50.0,
          vendas: [Venda(id: 'v2', data: '2026-04-10', qtd: 100, preco: 60.0)],
        ),
      ],
    );
    final antes = apurar(lucro).toJson();
    final a = apurar(prejuizo);
    expect(a.lucroLiquido, lessThan(0));
    expect(a.darf, 0.0);
    // O imposto do mês seguinte é só 15% do lucro dele: nada é abatido.
    final b = apurar(lucro);
    conferir(b.toJson(), antes);
    expect(b.irrf, 0.0);
    expect(b.ops.single.regime, 'Swing');
    expect(b.impSt, b.ops.single.liquido * aliqSwing);
    expect(b.darf, b.impSt);
  });
}
