import 'package:calculadoradarf/nucleo/ambiente.dart';
import 'package:calculadoradarf/nucleo/datas.dart';
import 'package:calculadoradarf/nucleo/erros.dart';
import 'package:calculadoradarf/nucleo/mercado/chart.dart';
import 'package:calculadoradarf/nucleo/modelos/barras.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/referencias.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

/// `_falso` do gerador: registra os params e devolve a resposta do intervalo
/// (ou a de chave `*`); sem resposta ou com `__erro__` lança como o Yahoo.
ObterChart _falso(Map<String, Object?> respostas, List<Object?> chamadas) {
  return (ticker, params) async {
    chamadas.add(Map<String, Object?>.of(params));
    final r = respostas[params['interval'] ?? '*'] ?? respostas['*'];
    final erro = r == null ? 'sem_dados' : _mapa(r)['__erro__'];
    if (erro == 'sem_dados') {
      throw SemDados('Sem dados para $ticker no Yahoo Finance.');
    }
    if (erro == 'limite') throw LimiteConsultas('Too Many Requests');
    return _mapa(r);
  };
}

Map<String, Object?> _erro(Object e) => {
  'erro': e.runtimeType.toString(),
  'mensagem': e.toString(),
};

Map<String, Object?> _barraJson(Barra b) => {
  'ts': b.ts,
  'dt': b.dt.iso(),
  'alta': b.alta,
  'baixa': b.baixa,
  'abre': b.abre,
};

Map<String, Object?> _diariasJson(Diarias r) => {
  'barras': [
    for (final b in r.barras)
      {
        'data': b.data,
        'abre': b.abre,
        'alta': b.alta,
        'baixa': b.baixa,
        'fech': b.fech,
      },
  ],
  'hoje': r.hoje,
  'preco': r.preco,
  'fonte': r.fonte,
};

Future<Object?> _executar(Caso c) async {
  final e = _mapa(c.entrada);
  final chamadas = <Object?>[];
  switch (c.funcao) {
    case 'historico_desde':
      final obter = _falso(_mapa(e['respostas']), chamadas);
      Map<String, Object?> saida;
      try {
        final h = await historicoDesde(
          e['ticker']! as String,
          DataHora.parse(e['desde']! as String),
          agora: DataHora.parse(e['agora']! as String),
          obterChart: obter,
        );
        saida = {
          'barras': [for (final b in h.barras) _barraJson(b)],
          'fonte': h.fonte,
          'intervalo': h.intervalo,
        };
      } on ErroNucleo catch (erro) {
        saida = _erro(erro);
      }
      return {...saida, 'chamadas': chamadas};
    case 'barras_diarias':
      final obter = _falso({'*': e['resposta']}, chamadas);
      final cache = CacheDiarias();
      final saidas = <Object?>[];
      for (final p in _lista(e['passos'])) {
        final passo = _mapa(p);
        ambiente = Ambiente.fixo(agora: (passo['agora']! as num).toDouble());
        try {
          saidas.add(
            _diariasJson(
              await cache.barrasDiarias(
                passo['ticker']! as String,
                desde: passo['desde'] as String?,
                obterChart: obter,
              ),
            ),
          );
        } on ErroNucleo catch (erro) {
          saidas.add(_erro(erro));
        }
      }
      return {'passos': saidas, 'chamadas': chamadas};
    case 'range_diarias':
      return {'range': rangeDiarias(e['desde'] as String?)};
    case 'dados_api':
      try {
        return dadosAtivoDeChart(
          e['ticker']! as String,
          _mapa(e['resposta']),
          nomeConhecido: e['nome_conhecido']! as String,
        ).toJson();
      } on ErroNucleo catch (erro) {
        return _erro(erro);
      }
  }
  throw StateError('função desconhecida: ${c.funcao}');
}

void main() {
  setUp(() => ambiente = Ambiente.fixo());
  tearDown(() => ambiente = Ambiente.sistema());

  final casos = carregarCasos('yahoo');

  test('referências foram geradas pelo Python 3.12', () {
    expect(versaoPythonDasReferencias('yahoo'), startsWith('3.12'));
    expect(casos, isNotEmpty);
  });

  for (final c in casos) {
    test('${c.funcao}: ${c.nome}', () async {
      conferir(await _executar(c), c.saida);
    });
  }

  test('o cache de barras diárias expira em 900 segundos', () {
    expect(CacheDiarias.validadeSegundos, 900);
  });

  test('limpar esvazia o cache', () async {
    final chamadas = <Object?>[];
    final resposta = {
      'meta': <String, Object?>{},
      'timestamp': [1761051600],
      'indicators': {
        'quote': [
          {
            'high': [11],
            'low': [9],
            'close': [10],
          },
        ],
      },
    };
    final obter = _falso({'*': resposta}, chamadas);
    final cache = CacheDiarias();
    await cache.barrasDiarias('PETR4', obterChart: obter);
    await cache.barrasDiarias('PETR4', obterChart: obter);
    expect(chamadas, hasLength(1));
    cache.limpar();
    await cache.barrasDiarias('PETR4', obterChart: obter);
    expect(chamadas, hasLength(2));
  });
}
