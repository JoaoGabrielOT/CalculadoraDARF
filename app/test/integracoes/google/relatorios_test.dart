import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _agora = 1761000000.0;

/// Os escopos da 2.6.0, antes do `drive.readonly`.
const escoposAntigos = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

Map<String, Object?> _f(String id, String data) => {
  'id': id,
  'name': 'relatorio-abertura-$data.json',
  'modifiedTime': '${data}T12:00:00.000Z',
};

RespostaFalsa _about() => RespostaFalsa(
  200,
  json: {
    'user': {'emailAddress': 'eu@exemplo.com'},
  },
);

/// Sessão com token válido; o pedido do login (about) sai de
/// `falso.pedidos`.
Future<(DriveRelatorios, ClienteFalso)> _montar(
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
  return (DriveRelatorios(sessao), falso);
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  test('constantes do pedido', () {
    expect(pastaRelatorios, '1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B');
    expect(
      consultaRelatorios,
      "'1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B' in parents and trashed = false "
      "and name contains 'relatorio-abertura-'",
    );
  });

  test('listar pagina com a consulta e os campos do pedido', () async {
    final (drive, falso) = await _montar([
      RespostaFalsa(
        200,
        json: {
          'nextPageToken': 'p2',
          'files': [_f('a', '2026-11-26'), _f('b', '2026-11-25')],
        },
      ),
      RespostaFalsa(
        200,
        json: {
          'files': [
            _f('c', '2026-11-24'),
            {'id': 'sem-nome'},
          ],
        },
      ),
    ]);
    final l = await drive.listar();
    expect(l.map((a) => (a.id, a.nome)), [
      ('a', 'relatorio-abertura-2026-11-26.json'),
      ('b', 'relatorio-abertura-2026-11-25.json'),
      ('c', 'relatorio-abertura-2026-11-24.json'),
    ]);
    expect(l.first.modificado, '2026-11-26T12:00:00.000Z');
    expect(falso.pedidos, hasLength(2));
    final q1 = falso.pedidos[0].url.queryParameters,
        q2 = falso.pedidos[1].url.queryParameters;
    expect(falso.pedidos[0].metodo, 'GET');
    expect(
      falso.pedidos[0].url.replace(query: '').toString(),
      '$urlDrive/files?',
    );
    expect(q1['q'], consultaRelatorios);
    expect(q1['fields'], 'nextPageToken,files(id,name,modifiedTime)');
    expect(
      (q1['pageSize'], q1.containsKey('pageToken'), q2['pageToken']),
      ('100', false, 'p2'),
    );
    expect(q2['q'], consultaRelatorios);
  });

  test('descarta itens sem id, name ou modifiedTime texto', () async {
    final (drive, _) = await _montar([
      RespostaFalsa(
        200,
        json: {
          'files': [
            {'name': 'relatorio-abertura-2026-11-26.json', 'modifiedTime': 'x'},
            {'id': 'a', 'modifiedTime': 'x'},
            {'id': 'b', 'name': 'relatorio-abertura-2026-11-25.json'},
            {'id': 'c', 'name': 'r.json', 'modifiedTime': 5},
            {'id': 7, 'name': 'r.json', 'modifiedTime': 'x'},
            'não é objeto',
            _f('ok', '2026-11-24'),
          ],
        },
      ),
    ]);
    expect((await drive.listar()).map((a) => a.id), ['ok']);
  });

  test('sem files na resposta → lista vazia', () async {
    final (drive, falso) = await _montar([RespostaFalsa(200, json: {})]);
    expect(await drive.listar(), isEmpty);
    expect(falso.pedidos, hasLength(1));
  });

  test('nextPageToken repetido → para na 2ª página', () async {
    final (drive, falso) = await _montar([
      RespostaFalsa(
        200,
        json: {
          'nextPageToken': 'p2',
          'files': [_f('a', '2026-11-26')],
        },
      ),
      RespostaFalsa(
        200,
        json: {
          'nextPageToken': 'p2',
          'files': [_f('b', '2026-11-25')],
        },
      ),
    ]);
    final l = await drive.listar();
    expect(l.map((a) => a.id), ['a', 'b']);
    expect(falso.pedidos, hasLength(2));
  });

  test('para depois de 50 páginas', () async {
    final (drive, falso) = await _montar([
      for (var i = 0; i < 51; i++)
        RespostaFalsa(
          200,
          json: {
            'nextPageToken': 'p${i + 1}',
            'files': [_f('a$i', '2026-11-26')],
          },
        ),
    ]);
    final l = await drive.listar();
    expect(l, hasLength(50));
    expect(falso.pedidos, hasLength(50));
  });

  test('baixar faz GET alt=media com o Bearer e devolve o mapa', () async {
    final (drive, falso) = await _montar([
      RespostaFalsa(200, json: {'data': '2026-11-26', 'titulo': 'Abertura'}),
    ]);
    expect(await drive.baixar('abc'), {
      'data': '2026-11-26',
      'titulo': 'Abertura',
    });
    final p = falso.pedidos.single;
    expect(p.metodo, 'GET');
    expect(
      p.url.toString(),
      'https://www.googleapis.com/drive/v3/files/abc?alt=media',
    );
    expect(p.cabecalhos['authorization'], 'Bearer ya29.a');
  });

  test('baixar com corpo que não é JSON → RespostaInvalida', () async {
    final (drive, _) = await _montar([RespostaFalsa(200, texto: 'não é json')]);
    await expectLater(
      drive.baixar('abc'),
      throwsA(
        isA<ErroGoogle>().having((e) => e, 'tipo', isA<RespostaInvalida>()),
      ),
    );
  });

  test('baixar com 500 → ErroGoogle, não RespostaInvalida', () async {
    final (drive, _) = await _montar([RespostaFalsa(500, texto: 'falhou')]);
    await expectLater(
      drive.baixar('abc'),
      throwsA(
        isA<ErroGoogle>()
            .having((e) => e.status, 'status', 500)
            .having((e) => e, 'tipo', isNot(isA<RespostaInvalida>())),
      ),
    );
  });

  test('escopos vêm da sessão', () async {
    final (drive, _) = await _montar([]);
    expect(drive.escopos, escoposGoogle);
  });

  test('podeLerRelatorios exige drive.readonly', () {
    expect(podeLerRelatorios(null), isFalse);
    expect(podeLerRelatorios([]), isFalse);
    expect(podeLerRelatorios(escoposAntigos), isFalse);
    expect(podeLerRelatorios(escoposGoogle), isTrue);
  });
}
