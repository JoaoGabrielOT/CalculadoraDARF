import 'dart:math' as math;

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../nucleo/apoio/referencias.dart';
import '../apoio/cliente_falso.dart';
import '../apoio/layout_python.dart';

const _agora = 1761000000.0;

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

RespostaFalsa _about() => RespostaFalsa(
  200,
  json: {
    'user': {'emailAddress': 'eu@exemplo.com'},
  },
);

RespostaFalsa _resposta(Object? bruta) {
  final m = _mapa(bruta);
  return RespostaFalsa(
    m['status']! as int,
    json: m['json'],
    texto: m['texto'] as String?,
  );
}

/// Sessão com token válido e e-mail `eu@exemplo.com`; os pedidos do login
/// (about) são descartados de `falso.pedidos`.
Future<(PlanilhaGoogle, ClienteFalso)> _montar(
  List<RespostaFalsa> respostas,
) async {
  final falso = ClienteFalso.fila([_about(), ...respostas]);
  final a = ArmazenamentoMemoria();
  gravarToken(
    a,
    TokenGoogle(
      token: 'ya29.a',
      refreshToken: '1//r',
      clientId: 'c.apps.googleusercontent.com',
      clientSecret: 's',
      expiry: DateTime.utc(2030),
    ),
  );
  final sessao = SessaoGoogle(
    http: ClienteHttp(falso, tempoLimite: const Duration(seconds: 30)),
    armazenamento: a,
    executar: executarDireto,
  );
  await sessao.carregarToken();
  falso.pedidos.clear();
  return (PlanilhaGoogle(sessao), falso);
}

Map<String, Object?> _propriedadesJson(PropriedadesAba p) => {
  'sheetId': p.sheetId,
  'title': p.titulo,
  'gridProperties': {
    if (p.linhas != null) 'rowCount': p.linhas,
    if (p.colunas != null) 'columnCount': p.colunas,
  },
};

Future<Object?> _chamar(PlanilhaGoogle p, Caso c) async {
  final args = _lista(_mapa(c.entrada)['args']);
  switch (c.funcao) {
    case 'criar_planilha':
      return p.criarPlanilha();
    case 'garantir_abas':
      final m = await p.garantirAbas(args[0]! as String);
      return {for (final e in m.entries) e.key: _propriedadesJson(e.value)};
    case 'escrever':
      await p.escrever(args[0]! as String, {
        for (final e in _mapa(args[1]).entries)
          e.key: [for (final l in _lista(e.value)) _lista(l)],
      });
      return null;
    case 'ler':
      return p.ler(args[0]! as String);
    case 'buscar_planilha':
      return p.buscarPlanilha(args[0]! as String);
    case 'planilha_existe':
      return p.planilhaExiste(args[0]! as String);
    case 'compartilhar':
      await p.compartilhar(args[0]! as String, args[1]! as String);
      return null;
    case 'descompartilhar':
      await p.descompartilhar(args[0]! as String, args[1]! as String);
      return null;
  }
  throw StateError('função desconhecida: ${c.funcao}');
}

void _conferirPedido(
  PedidoGravado r,
  Map<String, Object?> esperado,
  String id,
  int? resumo,
) {
  expect(r.metodo, esperado['metodo'], reason: id);
  expect(
    Uri(scheme: r.url.scheme, host: r.url.host, path: r.url.path).toString(),
    esperado['url'],
    reason: id,
  );
  conferir(
    {for (final e in r.url.queryParametersAll.entries) e.key: e.value},
    esperado['params'],
    caminho: '$id.params',
  );
  conferir(
    r.texto.isEmpty ? null : layoutPython(r.json, resumo),
    esperado['json'],
    caminho: '$id.json',
  );
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  for (final caso in carregarCasos('google_pedidos')) {
    test('repetição do Python: ${caso.nome}', () async {
      final entrada = _mapa(caso.entrada);
      final saida = _mapa(caso.saida);
      final respostas = [
        for (final r in _lista(entrada['respostas'])) _resposta(r),
      ];
      final eh401 = caso.nome == 'erro_401';
      // O Python desiste no 401; aqui o 401 renova o token e repete o pedido,
      // então a fila ganha a renovação e um segundo 401.
      if (eh401) {
        respostas.addAll([
          RespostaFalsa(200, json: {'access_token': 'n', 'expires_in': 3599}),
          respostas.first,
        ]);
      }
      final (p, falso) = await _montar(respostas);
      // a coluna Detalhes do Resumo é só da 2.1
      final resumo = idDoResumo(entrada['respostas']);
      final esperados = _lista(saida['pedidos']);
      Object? resultado;
      ErroGoogle? erro;
      try {
        resultado = await _chamar(p, caso);
      } on ErroGoogle catch (e) {
        erro = e;
      }
      final feitos = [
        for (final r in falso.pedidos)
          if (r.url.host != 'oauth2.googleapis.com') r,
      ];
      if (eh401) {
        expect(feitos, hasLength(2));
        _conferirPedido(
          feitos[1],
          _mapa(esperados[0]),
          'repetição do 401',
          resumo,
        );
        feitos.removeLast();
      }
      expect(feitos, hasLength(esperados.length));
      for (var i = 0; i < esperados.length; i++) {
        _conferirPedido(feitos[i], _mapa(esperados[i]), 'pedido $i', resumo);
      }
      if (saida.containsKey('erro')) {
        expect(erro, isNotNull, reason: 'esperava ${saida['erro']}');
        expect(erro.runtimeType.toString(), saida['erro']);
        expect(erro!.mensagem, saida['mensagem']);
        expect(erro.status, saida['status']);
      } else {
        expect(erro, isNull);
        conferir(leituraPython(resultado), saida['resultado']);
      }
    });
  }

  test('escrever com NaN não envia nada', () async {
    final (p, falso) = await _montar([
      RespostaFalsa(
        200,
        json: {
          'sheets': [
            for (final a in esquemaAbas)
              {
                'properties': {
                  'sheetId': 1,
                  'title': a.nome,
                  'gridProperties': {
                    'rowCount': 1000,
                    'columnCount': a.colunas.length,
                  },
                },
              },
          ],
        },
      ),
    ]);
    await expectLater(
      p.escrever('sid1', {
        'Compras': [
          [math.log(-1), 'x'],
        ],
      }),
      throwsA(isA<ErroGoogle>()),
    );
    expect(falso.pedidos, hasLength(1));
    expect(falso.pedidos.single.metodo, 'GET');
    expect(
      falso.pedidos.where((q) => q.url.path.contains('batchUpdate')),
      isEmpty,
    );
  });

  test('ler preserva int, double, bool e texto', () async {
    final (p, _) = await _montar([
      RespostaFalsa(
        200,
        json: {
          'sheets': [
            {
              'properties': {
                'title': 'Resumo',
                'gridProperties': {'columnCount': 13},
              },
            },
          ],
        },
      ),
      RespostaFalsa(
        200,
        json: {
          'valueRanges': [
            {
              'values': [
                [1, 2.5, true, 'a'],
              ],
            },
          ],
        },
      ),
    ]);
    final lido = (await p.ler('s'))['Resumo']!.single;
    expect(lido.take(4).toList(), [1, 2.5, true, 'a']);
    expect(lido[0], isA<int>());
    expect(lido[1], isA<double>());
    expect(lido[2], isA<bool>());
  });

  test('linkPlanilha', () {
    expect(linkPlanilha('abc'), 'https://docs.google.com/spreadsheets/d/abc');
  });
}
