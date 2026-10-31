import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/mercado/dados_ativo.dart';
import 'package:calculadoradarf/nucleo/mercado/indicadores.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:calculadoradarf/nucleo/modelos/config.dart';
import 'package:calculadoradarf/nucleo/radar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;
double? _num(Object? o) => o == null ? null : (o as num).toDouble();

List<BarraDiaria> _barras(Object? entrada) => [
  for (final b in _lista(_mapa(entrada)['barras']))
    BarraDiaria(
      data: '',
      alta: _num(_mapa(b)['alta'])!,
      baixa: _num(_mapa(b)['baixa'])!,
      fech: _num(_mapa(b)['fech'])!,
    ),
];

List<ItemRadar> _radar(Object? lista) => [
  for (final r in _lista(lista)) ItemRadar.fromJson(_mapa(r)),
];

List<Object?> _projetar(List<ItemRadar> radar) => [
  for (final r in radar)
    {'ticker': r.ticker, 'nome': r.nome, 'desde': r.desde, 'pos': r.pos},
];

Map<String, DadosAtivo> _dados(Object? m) => {
  for (final e in _mapa(m).entries) e.key: DadosAtivo.fromJson(_mapa(e.value)),
};

Object? _executar(Caso c) {
  final e = _mapa(c.entrada);
  switch (c.funcao) {
    case 'indicadores':
      final barras = _barras(e);
      final h = [for (final b in barras) b.alta];
      final l = [for (final b in barras) b.baixa];
      final f = [for (final b in barras) b.fech];
      return {
        'atr14': calcularAtr(h, l, f, 14),
        'atr22': calcularAtr(h, l, f, 22),
        'chandelier': calcularChandelier(barras),
        'chandelier_5_2': calcularChandelier(barras, n: 5, mult: 2),
        'serie': serieChandelier(barras),
        'serie_5_2': serieChandelier(barras, n: 5, mult: 2),
      };
    case 'pivos':
      final p = calcularPivos(
        _num(e['alta'])!,
        _num(e['baixa'])!,
        _num(e['fech'])!,
      );
      return {'pp': p.pp, 'r1': p.r1, 's1': p.s1};
    case 'risco':
      final valores = _lista(e['valores']);
      return {
        for (final (i, v) in valores.indexed)
          '$i': () {
            final r = classificarRisco(_num(v)!);
            return [r.rotulo, r.fundo, r.texto];
          }(),
      };
    case 'variacao':
      return {
        'resultados': [
          for (final p in _lista(e['pares']))
            () {
              final par = _lista(p);
              final r = variacao(_num(par[0]), _num(par[1]));
              return [r.$1, r.$2];
            }(),
        ],
      };
    case 'anterior_de':
      return {
        'anterior': anteriorDe([
          for (final p in _lista(e['pares']))
            (_lista(p)[0]! as String, _num(_lista(p)[1])!),
        ], e['dia']! as String),
      };
    case 'ordenar_radar':
      return {
        'tickers': [for (final r in ordenarRadar(_radar(e['radar']))) r.ticker],
      };
    case 'adicionar_radar':
      final cfg = Config(radar: _radar(e['radar']));
      final item = adicionarRadar(
        cfg,
        e['ticker']! as String,
        nome: e['nome']! as String,
      );
      return {
        'item': item == null ? null : _projetar([item])[0],
        'radar': _projetar(cfg.radar),
      };
    case 'reordenar_radar':
      final cfg = Config(radar: _radar(e['radar']));
      reordenarRadar(cfg, [for (final t in _lista(e['tickers'])) t! as String]);
      return {'radar': _projetar(cfg.radar)};
    case 'filtrar_ordenar':
      final itens = _radar(e['itens']);
      final dados = _dados(e['dados']);
      final custodia = {for (final t in _lista(e['custodia'])) t! as String};
      return {
        for (final f in filtrosRadar)
          for (final o in [...ordensRadar.map((x) => x.$1), 'desconhecida'])
            '$f|$o': [
              for (final i in filtrarOrdenar(
                itens,
                dados,
                filtro: f,
                ordem: o,
                custodia: custodia,
              ))
                i.ticker,
            ],
      };
    case 'resumo_dia':
      final r = resumoDia([
        for (final t in _lista(e['tickers'])) t! as String,
      ], _dados(e['dados']));
      return {
        'resumo': [r.$1, r.$2, r.$3],
      };
  }
  throw StateError('função desconhecida: ${c.funcao}');
}

void main() {
  setUp(() => ambiente = Ambiente.fixo());

  final casos = carregarCasos('mercado');

  test('referências foram geradas pelo Python 3.12', () {
    expect(versaoPythonDasReferencias('mercado'), startsWith('3.12'));
    expect(casos, isNotEmpty);
  });

  for (final c in casos) {
    test('${c.funcao}: ${c.nome}', () => conferir(_executar(c), c.saida));
  }

  group('entradas fora do JSON', () {
    test('NaN não é válido e cai na última faixa de risco', () {
      expect(valido(double.nan), isFalse);
      expect(valido(null), isFalse);
      expect(valido(0), isFalse);
      expect(valido(0.01), isTrue);
      expect(variacao(double.nan, 1.0), (null, null));
      expect(classificarRisco(double.nan).rotulo, 'Alto Risco / Muito Alto');
    });

    test('constantes de faixas e ordens', () {
      expect(filtrosRadar, ['Todos', 'Em alta', 'Em queda', 'Em carteira']);
      expect(ordensRadar.length, 6);
      expect(periodosGrafico['Máx'], ('max', '1mo', 3600));
      expect(periodosGrafico.keys.first, '1D');
    });

    test('DadosAtivo vai e volta pelas chaves do Python', () {
      final json = {
        'ticker': 'PETR4',
        'nome': 'Petrobras',
        'preco': 30.5,
        'media6m': 29.0,
        'atr': 1.0,
        'atr_pct': 3.2,
        'risco': ['Alto Risco', '#f97316', '#ffffff'],
        'hora': 1761000000.5,
        'anterior': 30.0,
        'var': 0.5,
        'var_pct': 1.6,
        'min6m': 25.0,
        'max6m': 35.0,
        'var6m_pct': 2.0,
        'vs_media_pct': 5.0,
        'max_dia': 31.0,
        'min_dia': 30.0,
        'max52': 40.0,
        'min52': 20.0,
        'volume': 1000000.0,
      };
      final d = DadosAtivo.fromJson(json);
      expect(d.variacaoPct, 1.6);
      expect(d.risco?.rotulo, 'Alto Risco');
      conferir(d.toJson(), json);
    });
  });
}
