import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _agora = 1761000000.0;
const _pasta = '1pIy2wYGucMq_1Jitg96yWy8Bxu4ytn5B';

RespostaFalsa _about() => RespostaFalsa(
  200,
  json: {
    'user': {'emailAddress': 'dono@gmail.com'},
  },
);

RespostaFalsa _pastaGet({
  required bool canShare,
  String dono = 'Dono@Gmail.com',
}) => RespostaFalsa(
  200,
  json: {
    'capabilities': {'canShare': canShare},
    'owners': [
      {'emailAddress': dono},
    ],
  },
);

RespostaFalsa _erro(int status, String motivo, [String msg = 'falhou']) =>
    RespostaFalsa(
      status,
      json: {
        'error': {
          'code': status,
          'message': msg,
          'errors': [
            {'reason': motivo, 'message': msg},
          ],
        },
      },
    );

Map<String, Object?> _perm(String email, String papel) => {
  'emailAddress': email,
  'role': papel,
  'type': 'user',
};

/// Sessão com token válido e os escopos [escopos]; o pedido do login
/// (about) sai de `falso.pedidos`.
Future<(DriveCompartilhamento, ClienteFalso)> _montar(
  List<RespostaFalsa> respostas, {
  List<String> escopos = const [...escoposGoogle, escopoDrive],
  RespostaFalsa Function(PedidoGravado)? responder,
}) async {
  final falso = responder == null
      ? ClienteFalso.fila([_about(), ...respostas])
      : ClienteFalso(
          (p) => p.url.path.endsWith('/about') ? _about() : responder(p),
        );
  final a = ArmazenamentoMemoria();
  gravarToken(
    a,
    TokenGoogle(
      token: 'ya29.a',
      refreshToken: '1//r',
      clientId: 'c.apps.googleusercontent.com',
      clientSecret: 's',
      expiry: DateTime.utc(2030),
      scopes: escopos,
    ),
  );
  final sessao = SessaoGoogle(
    http: ClienteHttp(falso, tempoLimite: const Duration(seconds: 30)),
    armazenamento: a,
    executar: executarDireto,
  );
  await sessao.carregarToken();
  falso.pedidos.clear();
  return (DriveCompartilhamento(sessao), falso);
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(agora: _agora));
  tearDown(() => ambiente = Ambiente.sistema());

  test('escopoDrive e escoposGoogle sem ele', () {
    expect(escopoDrive, 'https://www.googleapis.com/auth/drive');
    expect(escoposGoogle, isNot(contains(escopoDrive)));
  });

  group('estado', () {
    test('canShare false: não dono', () async {
      final (drive, falso) = await _montar([_pastaGet(canShare: false)]);
      expect(await drive.estado(), EstadoCompartilhamento.naoDono);
      final p = falso.pedidos.single;
      expect(p.metodo, 'GET');
      expect(p.url.path, '/drive/v3/files/$_pasta');
      expect(
        p.url.queryParameters['fields'],
        'capabilities(canShare),owners(emailAddress)',
      );
    });

    test('editor com canShare, fora de owners: não dono', () async {
      final (drive, _) = await _montar([
        _pastaGet(canShare: true, dono: 'outra@gmail.com'),
      ]);
      expect(await drive.estado(), EstadoCompartilhamento.naoDono);
    });

    test('canShare sem owners: não dono', () async {
      final (drive, _) = await _montar([
        RespostaFalsa(
          200,
          json: {
            'capabilities': {'canShare': true},
          },
        ),
      ]);
      expect(await drive.estado(), EstadoCompartilhamento.naoDono);
    });

    test('503 na conferência: o erro sobe (não conferido)', () async {
      final (drive, _) = await _montar([_erro(503, 'backendError')]);
      await expectLater(drive.estado(), throwsA(isA<ErroGoogle>()));
    });

    test('pasta que a conta não enxerga (404): não dono', () async {
      final (drive, _) = await _montar([_erro(404, 'notFound')]);
      expect(await drive.estado(), EstadoCompartilhamento.naoDono);
    });

    test('403 de permissão (ou sem reason): não dono', () async {
      for (final resposta in [
        _erro(403, 'insufficientFilePermissions'),
        _erro(403, 'forbidden'),
        _erro(403, 'notFound'),
        RespostaFalsa(
          403,
          json: {
            'error': {'code': 403, 'message': 'Proibido'},
          },
        ),
        RespostaFalsa(403, texto: 'Forbidden'),
      ]) {
        final (drive, _) = await _montar([resposta]);
        expect(await drive.estado(), EstadoCompartilhamento.naoDono);
      }
    });

    test('403 de limite: o erro sobe (não conferido)', () async {
      for (final motivo in [
        'rateLimitExceeded',
        'userRateLimitExceeded',
        'dailyLimitExceeded',
      ]) {
        final (drive, _) = await _montar([_erro(403, motivo)]);
        await expectLater(
          drive.estado(),
          throwsA(isA<ErroGoogle>().having((e) => e.status, 'status', 403)),
          reason: motivo,
        );
      }
    });

    test('403 de limite em compartilharCom: vazio, sem estado', () async {
      final (drive, _) = await _montar([_erro(403, 'userRateLimitExceeded')]);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.estado, isNull);
      expect(r.erro, isNull);
    });

    test('dono sem o escopo drive: semEscopo', () async {
      final (drive, _) = await _montar([
        _pastaGet(canShare: true),
      ], escopos: escoposGoogle);
      expect(await drive.estado(), EstadoCompartilhamento.semEscopo);
    });

    test('dono com o escopo drive: pronto', () async {
      final (drive, _) = await _montar([_pastaGet(canShare: true)]);
      expect(await drive.estado(), EstadoCompartilhamento.pronto);
    });

    test('sem internet: o erro sobe', () async {
      final (drive, _) = await _montar([
        RespostaFalsa(0, erro: const SocketException('sem rede')),
      ]);
      await expectLater(drive.estado(), throwsA(isA<Offline>()));
    });
  });

  group('compartilharCom', () {
    test('não dono: nenhum pedido de permissão', () async {
      final (drive, falso) = await _montar([_pastaGet(canShare: false)]);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.estado, EstadoCompartilhamento.naoDono);
      expect(r.compartilhados, 0);
      expect(r.recusados, isEmpty);
      expect(r.semEscopo, isFalse);
      expect(r.erro, isNull);
      expect(falso.pedidos, hasLength(1));
    });

    test('503 na conferência: resultado vazio, sem erro', () async {
      final (drive, falso) = await _montar([_erro(503, 'backendError')]);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.estado, isNull);
      expect(r.erro, isNull);
      expect(r.semEscopo, isFalse);
      expect(r.compartilhados, 0);
      expect(falso.pedidos, hasLength(1));
    });

    test('429 ou resposta inválida na conferência: vazio, sem erro', () async {
      for (final resposta in [
        _erro(429, 'rateLimitExceeded'),
        RespostaFalsa(200, texto: 'não é json'),
      ]) {
        final (drive, _) = await _montar([resposta]);
        final r = await drive.compartilharCom(['bia@gmail.com']);
        expect(r.estado, isNull);
        expect(r.erro, isNull);
      }
    });

    test('dono sem escopo: semEscopo, sem listar nem criar', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
      ], escopos: escoposGoogle);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.semEscopo, isTrue);
      expect(r.compartilhados, 0);
      expect(falso.pedidos, hasLength(1));
    });

    test('lista as permissões (2 páginas) e cria só para quem falta', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(
          200,
          json: {
            'nextPageToken': 'p2',
            'permissions': [
              _perm('dono@gmail.com', 'owner'),
              _perm(' Ana@Gmail.com ', 'writer'),
            ],
          },
        ),
        RespostaFalsa(
          200,
          json: {
            'permissions': [
              _perm('caio@gmail.com', 'reader'),
              {'role': 'reader', 'type': 'anyone'},
            ],
          },
        ),
        RespostaFalsa(200, json: {'id': 'perm-bia'}),
        RespostaFalsa(200, json: {'id': 'perm-davi'}),
      ]);
      final r = await drive.compartilharCom([
        'ana@gmail.com',
        'bia@gmail.com',
        'CAIO@gmail.com',
        ' davi@gmail.com',
      ]);
      expect(r.estado, EstadoCompartilhamento.pronto);
      expect(r.compartilhados, 2);
      expect(r.recusados, isEmpty);
      expect(r.semEscopo, isFalse);
      expect(r.erro, isNull);

      final lista = falso.pedidos.sublist(1, 3);
      for (final p in lista) {
        expect(p.metodo, 'GET');
        expect(p.url.path, '/drive/v3/files/$_pasta/permissions');
        expect(
          p.url.queryParameters['fields'],
          'nextPageToken,permissions(emailAddress,role,type)',
        );
      }
      expect(lista[0].url.queryParameters.containsKey('pageToken'), isFalse);
      expect(lista[1].url.queryParameters['pageToken'], 'p2');

      final criados = falso.pedidos.sublist(3);
      expect(criados, hasLength(2));
      for (final p in criados) {
        expect(p.metodo, 'POST');
        expect(p.url.path, '/drive/v3/files/$_pasta/permissions');
        expect(p.url.queryParameters['sendNotificationEmail'], 'false');
        expect(p.url.queryParameters['fields'], 'emailAddress');
        expect(p.cabecalhos['content-type'], 'application/json');
      }
      expect(criados.map((p) => p.json), [
        {'role': 'reader', 'type': 'user', 'emailAddress': 'bia@gmail.com'},
        {'role': 'reader', 'type': 'user', 'emailAddress': 'davi@gmail.com'},
      ]);
    });

    test('e-mail sem conta Google no meio de 3: os outros 2 compartilhados '
        'e o inválido listado', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
        RespostaFalsa(200, json: {'id': '1'}),
        _erro(400, 'invalidSharingRequest'),
        RespostaFalsa(200, json: {'id': '3'}),
      ]);
      final r = await drive.compartilharCom([
        'ana@gmail.com',
        'sem@conta.com',
        'caio@gmail.com',
      ]);
      expect(r.compartilhados, 2);
      expect(r.recusados, ['sem@conta.com']);
      expect(r.erro, isNull);
      expect(falso.pedidos.where((p) => p.metodo == 'POST'), hasLength(3));
    });

    test('403 sem escopo ao criar: semEscopo com o motivo', () async {
      final (drive, _) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
        _erro(403, 'insufficientPermissions', 'Insufficient Permission'),
      ]);
      final r = await drive.compartilharCom([
        'bia@gmail.com',
        'caio@gmail.com',
      ]);
      expect(r.semEscopo, isTrue);
      expect(r.compartilhados, 0);
      expect(r.erro, 'Insufficient Permission');
    });

    test('outro 403 ao criar: para com o motivo', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
        _erro(403, 'forbidden', 'Proibido'),
      ]);
      final r = await drive.compartilharCom([
        'bia@gmail.com',
        'caio@gmail.com',
      ]);
      expect(r.semEscopo, isFalse);
      expect(r.compartilhados, 0);
      expect(r.erro, 'Proibido');
      expect(falso.pedidos.where((p) => p.metodo == 'POST'), hasLength(1));
    });

    test('sem internet na conferência: vazio, sem erro', () async {
      final (drive, _) = await _montar([
        RespostaFalsa(0, erro: const SocketException('sem rede')),
      ]);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.estado, isNull);
      expect(r.erro, isNull);
      expect(r.compartilhados, 0);
    });

    test('sem internet depois de conferir o dono: erro no resultado', () async {
      final (drive, _) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(0, erro: const SocketException('sem rede')),
      ]);
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(r.estado, EstadoCompartilhamento.pronto);
      expect(r.erro, isNotNull);
    });

    test('recusado (400) não é tentado de novo nem listado de novo', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
        _erro(400, 'invalidSharingRequest'),
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
      ]);
      expect((await drive.compartilharCom(['sem@conta.com'])).recusados, [
        'sem@conta.com',
      ]);
      final r = await drive.compartilharCom(['sem@conta.com']);
      expect(r.recusados, isEmpty);
      expect(falso.pedidos.where((p) => p.metodo == 'POST'), hasLength(1));
    });

    test('e-mail normalizado pelo Drive não gera um segundo POST', () async {
      final (drive, falso) = await _montar([
        _pastaGet(canShare: true),
        RespostaFalsa(200, json: {'permissions': <Object?>[]}),
        RespostaFalsa(200, json: {'emailAddress': 'JoaoSilva@gmail.com'}),
        _pastaGet(canShare: true),
        RespostaFalsa(
          200,
          json: {
            'permissions': [_perm('joaosilva@gmail.com', 'reader')],
          },
        ),
      ]);
      final amigo = ['joao.silva@googlemail.com'];
      expect((await drive.compartilharCom(amigo)).compartilhados, 1);
      final r = await drive.compartilharCom(amigo);
      expect(r.compartilhados, 0);
      expect(r.erro, isNull);
      expect(falso.pedidos.where((p) => p.metodo == 'POST'), hasLength(1));
    });

    test('nextPageToken repetido encerra a listagem', () async {
      var listagens = 0;
      final (drive, falso) = await _montar(
        const [],
        responder: (p) {
          if (p.url.path == '/drive/v3/files/$_pasta') {
            return _pastaGet(canShare: true);
          }
          if (p.metodo == 'GET') {
            listagens++;
            return RespostaFalsa(
              200,
              json: {
                'nextPageToken': 'mesmo',
                'permissions': [_perm('bia@gmail.com', 'reader')],
              },
            );
          }
          return RespostaFalsa(200, json: {'emailAddress': 'x@gmail.com'});
        },
      );
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(listagens, 2);
      expect(r.compartilhados, 0);
      expect(falso.pedidos.where((p) => p.metodo == 'POST'), isEmpty);
    });

    test('a listagem para em 50 páginas', () async {
      var listagens = 0;
      final (drive, _) = await _montar(
        const [],
        responder: (p) {
          if (p.url.path == '/drive/v3/files/$_pasta') {
            return _pastaGet(canShare: true);
          }
          if (p.metodo == 'GET') {
            listagens++;
            return RespostaFalsa(
              200,
              json: {
                'nextPageToken': 'p$listagens',
                'permissions': <Object?>[],
              },
            );
          }
          return RespostaFalsa(200, json: {'emailAddress': 'bia@gmail.com'});
        },
      );
      final r = await drive.compartilharCom(['bia@gmail.com']);
      expect(listagens, 50);
      expect(r.compartilhados, 1);
    });

    test('lista vazia de amigos: só confere o dono', () async {
      final (drive, falso) = await _montar([_pastaGet(canShare: true)]);
      final r = await drive.compartilharCom(const []);
      expect(r.compartilhados, 0);
      expect(falso.pedidos, hasLength(1));
    });
  });
}
