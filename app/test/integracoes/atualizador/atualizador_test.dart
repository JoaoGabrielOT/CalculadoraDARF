import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:calculadoradarf/versao.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../nucleo/apoio/referencias.dart';
import '../apoio/cliente_falso.dart';

Map<String, Object?> _mapa(Object? o) => o! as Map<String, Object?>;
List<Object?> _lista(Object? o) => o! as List<Object?>;

ClienteHttp _cliente(http.Client falso) => ClienteHttp(falso);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

InfoAtualizacao _info(List<int> conteudo, {int? tamanho, String? sha}) =>
    InfoAtualizacao(
      versao: '2.1.0',
      notas: '',
      url: 'https://github.com/x/releases/download/v2.1.0/CalculadoraDARF.exe',
      tamanho: tamanho ?? conteudo.length,
      sha256: sha ?? _sha(conteudo),
    );

/// Cliente cujo corpo entrega [blocos] e depois falha com [erro].
class _ClienteQueda extends http.BaseClient {
  _ClienteQueda(this.blocos, this.erro);

  final List<List<int>> blocos;
  final Object erro;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    Stream<List<int>> corpo() async* {
      for (final b in blocos) {
        yield b;
      }
      throw erro;
    }

    return http.StreamedResponse(corpo(), 200);
  }
}

void main() {
  late Directory pasta;
  late File destino;

  setUp(() {
    pasta = Directory.systemTemp.createTempSync('atualizador_test');
    destino = File('${pasta.path}/CalculadoraDARF.novo.exe');
  });

  tearDown(() => pasta.deleteSync(recursive: true));

  /// Nada sobra na pasta: nem o arquivo final nem parciais.
  void naoSobraNada() => expect(pasta.listSync(), isEmpty);

  group('versao_tupla do Python', () {
    for (final c in carregarCasos('atualizador')) {
      if (c.funcao != 'versao_tupla') continue;
      test('versaoTupla: ${c.nome}', () {
        final (a, b, d) = versaoTupla(c.entrada! as String);
        conferir([a, b, d], c.saida);
      });
    }
  });

  group('verificar do Python', () {
    for (final c in carregarCasos('atualizador')) {
      if (c.funcao != 'verificar') continue;
      // O corpo "rate limit exceeded" agora vira a mensagem de limite (grupo
      // 'manifesto versao.json'); o 403 comum segue coberto abaixo.
      if (c.nome == 'http 403') continue;
      test('verificar: ${c.nome}', () async {
        final e = _mapa(c.entrada);
        final saida = _mapa(c.saida);
        final falso = ClienteFalso.fila([
          RespostaFalsa(404),
          RespostaFalsa(
            e['status']! as int,
            json: e['json'],
            motivo: switch (e['status']! as int) {
              403 => 'Forbidden',
              500 => 'Internal Server Error',
              _ => null,
            },
          ),
        ]);
        Object? resultado;
        Object? erro;
        try {
          final info = await verificarAtualizacao(
            _cliente(falso),
            nomeAsset: e['nome_asset']! as String,
            versaoAtual: e['versao_atual']! as String,
            executar: executarDireto,
          );
          resultado = info == null
              ? null
              : {
                  'versao': info.versao,
                  'notas': info.notas,
                  'url': info.url,
                  'tamanho': info.tamanho,
                  'sha256': info.sha256,
                };
        } catch (ex) {
          erro = ex;
        }

        final pedidos = _lista(saida['pedidos']);
        // O primeiro pedido é o manifesto (404 aqui); o resto é o do Python.
        expect(falso.pedidos, hasLength(pedidos.length + 1));
        expect(falso.pedidos.first.url.toString(), urlManifesto);
        final esperado = _mapa(pedidos.single);
        final pedido = falso.pedidos.last;
        expect(pedido.metodo, esperado['metodo']);
        expect(pedido.url.toString(), esperado['url']);
        final cab = _mapa(esperado['cabecalhos']);
        expect(pedido.cabecalhos['accept'], cab['Accept']);
        expect(pedido.cabecalhos['user-agent'], cab['User-Agent']);

        if (saida.containsKey('erro')) {
          expect(erro, isA<ErroHttp>(), reason: '$erro');
          expect(erro.toString(), saida['mensagem']);
        } else {
          expect(erro, isNull);
          conferir(resultado, saida['resultado']);
        }
      });
    }
  });

  test('a 2.0.0 é mais nova que a 1.12.1 e o app já sai na 2.11.0', () {
    expect(versaoMaisNova('v2.0.0', '1.12.1'), isTrue);
    expect(versaoMaisNova('v2.0.0', '2.0.0'), isFalse);
    expect(versaoMaisNova('v1.12.1', '2.0.0'), isFalse);
    expect(versaoMaisNova('v1.12.1', '1.12.0'), isTrue);
    expect(versaoMaisNova('2.0.10', '2.0.9'), isTrue);
    expect(versaoMaisNova('2.0.9', '2.0.10'), isFalse);
    expect(versaoApp, '2.11.0');
  });

  test('constantes e asset da plataforma', () {
    expect(repositorioGithub, 'JoaoGabrielOT/CalculadoraDARF');
    expect(
      urlUltimaVersao,
      'https://api.github.com/repos/JoaoGabrielOT/CalculadoraDARF/'
      'releases/latest',
    );
    expect(
      urlManifesto,
      'https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/latest/'
      'download/versao.json',
    );
    expect(nomeAssetWindows, 'CalculadoraDARF.exe');
    expect(nomeAssetAndroid, 'CalculadoraDARF.apk');
  });

  test('nomeAssetDaPlataforma', () {
    expect(nomeAssetDaPlataforma(windows: true), 'CalculadoraDARF.exe');
    expect(nomeAssetDaPlataforma(windows: false), 'CalculadoraDARF.apk');
  });

  for (final corpo in ['<html>erro</html>', '[1, 2]']) {
    test('verificar: corpo 200 que não é objeto JSON ($corpo)', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(404),
        RespostaFalsa(200, texto: corpo),
      ]);
      await expectLater(
        verificarAtualizacao(
          _cliente(falso),
          nomeAsset: nomeAssetWindows,
          executar: executarDireto,
        ),
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Resposta inválida do GitHub.',
          ),
        ),
      );
    });
  }

  test('verificar: falha de transporte vira ErroConexao', () async {
    final falso = ClienteFalso.fila([
      RespostaFalsa(200, erro: const SocketException('sem rede')),
      RespostaFalsa(200, erro: const SocketException('sem rede')),
    ]);
    await expectLater(
      verificarAtualizacao(
        _cliente(falso),
        nomeAsset: nomeAssetWindows,
        executar: executarDireto,
      ),
      throwsA(isA<ErroConexao>()),
    );
  });

  group('manifesto versao.json', () {
    const sha =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    Map<String, Object?> manifesto({String versao = '2.11.0'}) => {
      'versao': versao,
      'notas': '  Notas da versão.\n',
      'assets': {
        'CalculadoraDARF.exe': {'tamanho': 1234, 'sha256': sha},
        'CalculadoraDARF.apk': {'tamanho': 99, 'sha256': 'ab' * 32},
      },
    };

    Future<InfoAtualizacao?> verificar(ClienteFalso falso, {String? asset}) =>
        verificarAtualizacao(
          _cliente(falso),
          nomeAsset: asset ?? nomeAssetWindows,
          versaoAtual: '2.10.0',
          executar: executarDireto,
        );

    final releaseApi = {
      'tag_name': 'v2.11.0',
      'body': 'Notas da API',
      'assets': [
        {
          'name': 'CalculadoraDARF.exe',
          'browser_download_url': 'https://exemplo/api.exe',
          'size': 7,
          'digest': 'sha256:$sha',
        },
      ],
    };

    test('válido: usa o manifesto e não chama a API', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, json: manifesto())]);
      final info = await verificar(falso);
      expect(falso.pedidos, hasLength(1));
      expect(falso.pedidos.single.url.toString(), urlManifesto);
      expect(info, isNotNull);
      expect(info!.versao, '2.11.0');
      expect(info.notas, 'Notas da versão.');
      expect(
        info.url,
        'https://github.com/JoaoGabrielOT/CalculadoraDARF/releases/download/'
        '2.11.0/CalculadoraDARF.exe',
      );
      expect(info.tamanho, 1234);
      expect(info.sha256, sha);
    });

    test('válido para o APK', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, json: manifesto())]);
      final info = await verificar(falso, asset: nomeAssetAndroid);
      expect(info!.url, endsWith('/2.11.0/CalculadoraDARF.apk'));
      expect(info.tamanho, 99);
    });

    test('404: cai na API', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(404),
        RespostaFalsa(200, json: releaseApi),
      ]);
      final info = await verificar(falso);
      expect(falso.pedidos, hasLength(2));
      expect(falso.pedidos.last.url.toString(), urlUltimaVersao);
      expect(info!.url, 'https://exemplo/api.exe');
    });

    test('versão não mais nova: null, sem chamar a API', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, json: manifesto(versao: '2.10.0')),
      ]);
      expect(await verificar(falso), isNull);
      expect(falso.pedidos, hasLength(1));
    });

    test('sem o asset da plataforma: null, sem chamar a API', () async {
      final m = manifesto()
        ..['assets'] = <String, Object?>{
          'CalculadoraDARF.apk': <String, Object?>{},
        };
      final falso = ClienteFalso.fila([RespostaFalsa(200, json: m)]);
      expect(await verificar(falso), isNull);
      expect(falso.pedidos, hasLength(1));
    });

    test('JSON inválido: cai na API', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, texto: '<html>'),
        RespostaFalsa(200, json: releaseApi),
      ]);
      final info = await verificar(falso);
      expect(falso.pedidos, hasLength(2));
      expect(info!.url, 'https://exemplo/api.exe');
    });

    test('falha de rede no manifesto: cai na API', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(200, erro: const SocketException('sem rede')),
        RespostaFalsa(200, json: releaseApi),
      ]);
      final info = await verificar(falso);
      expect(falso.pedidos, hasLength(2));
      expect(info!.versao, '2.11.0');
    });

    test('API com 403 sem limite: segue o ErroHttp de sempre', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(404),
        RespostaFalsa(403, json: {'message': 'Forbidden'}, motivo: 'Forbidden'),
      ]);
      await expectLater(verificar(falso), throwsA(isA<ErroHttp>()));
    });

    for (final (status, cab, texto) in [
      (403, {'x-ratelimit-remaining': '0'}, 'x'),
      (429, {'x-ratelimit-remaining': '0'}, 'x'),
      (403, <String, String>{}, '{"message":"API rate limit exceeded"}'),
    ]) {
      test('API com limite ($status, $cab): ErroAtualizacao', () async {
        final falso = ClienteFalso.fila([
          RespostaFalsa(404),
          RespostaFalsa(status, texto: texto, cabecalhos: cab),
        ]);
        await expectLater(
          verificar(falso),
          throwsA(
            isA<ErroAtualizacao>().having(
              (e) => e.mensagem,
              'mensagem',
              'O GitHub limitou as consultas deste endereço de internet. '
                  'Tente de novo em alguns minutos.',
            ),
          ),
        );
      });
    }
  });

  group('baixar', () {
    final conteudo = utf8.encode('0123456789abcdefghij');
    final blocos = [
      conteudo.sublist(0, 8),
      conteudo.sublist(8, 15),
      conteudo.sublist(15),
    ];

    test('progresso por bloco com o total do Content-Length', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(
          200,
          blocos: blocos,
          cabecalhos: {'Content-Length': '${conteudo.length}'},
        ),
      ]);
      final passos = <(int, int)>[];
      final arquivo = await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo, tamanho: 0),
        destino,
        progresso: (b, t) => passos.add((b, t)),
      );
      expect(arquivo.path, destino.path);
      expect(arquivo.readAsBytesSync(), conteudo);
      expect(passos, [(8, 20), (15, 20), (20, 20)]);
      expect(falso.pedidos.single.cabecalhos['user-agent'], 'CalculadoraDARF');
      expect(falso.pedidos.single.url.toString(), _info(conteudo).url);
      expect(pasta.listSync(), hasLength(1));
    });

    test('progresso com o total do tamanho publicado', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      final passos = <(int, int)>[];
      await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo),
        destino,
        progresso: (b, t) => passos.add((b, t)),
      );
      expect(passos.map((p) => p.$2), [20, 20, 20]);
    });

    test('sem Content-Length nem tamanho, o total é 0', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      final passos = <(int, int)>[];
      await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo, tamanho: 0, sha: ''),
        destino,
        progresso: (b, t) => passos.add((b, t)),
      );
      expect(passos.map((p) => p.$2), [0, 0, 0]);
      expect(destino.readAsBytesSync(), conteudo);
    });

    test('sem sha256 publicado não confere hash', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo, sha: ''),
        destino,
      );
      expect(destino.readAsBytesSync(), conteudo);
    });

    test('o parcial não usa o nome final durante o download', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      var vistoDurante = false;
      await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo),
        destino,
        progresso: (b, t) {
          if (b < t && destino.existsSync()) vistoDurante = true;
        },
      );
      expect(vistoDurante, isFalse);
      expect(destino.existsSync(), isTrue);
    });

    test('tamanho diferente: incompleto e arquivo apagado', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await expectLater(
        baixarAtualizacao(
          _cliente(falso),
          _info(conteudo, tamanho: 25),
          destino,
        ),
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.toString(),
            'mensagem',
            'O download ficou incompleto.',
          ),
        ),
      );
      naoSobraNada();
    });

    test('sha256 diferente: não confere e arquivo apagado', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await expectLater(
        baixarAtualizacao(
          _cliente(falso),
          _info(conteudo, sha: _sha(utf8.encode('outro'))),
          destino,
        ),
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.toString(),
            'mensagem',
            'O arquivo baixado não confere com o publicado.',
          ),
        ),
      );
      naoSobraNada();
    });

    test('sha256 em maiúsculas confere', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await baixarAtualizacao(
        _cliente(falso),
        _info(conteudo, sha: _sha(conteudo).toUpperCase()),
        destino,
      );
      expect(destino.readAsBytesSync(), conteudo);
    });

    test(
      'cancelar no meio: cancelada, conexão abortada e arquivo apagado',
      () async {
        final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
        var baixado = 0;
        await expectLater(
          baixarAtualizacao(
            _cliente(falso),
            _info(conteudo),
            destino,
            progresso: (b, t) => baixado = b,
            cancelado: () => baixado >= 8,
          ),
          throwsA(
            isA<ErroAtualizacao>().having(
              (e) => e.toString(),
              'mensagem',
              'Atualização cancelada.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(baixado, 8);
        expect(falso.abortados, 1);
        naoSobraNada();
      },
    );

    test('cancelado desde o início: nada é pedido ao arquivo', () async {
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await expectLater(
        baixarAtualizacao(
          _cliente(falso),
          _info(conteudo),
          destino,
          cancelado: () => true,
        ),
        throwsA(isA<ErroAtualizacao>()),
      );
      naoSobraNada();
    });

    test('queda de rede no meio: ErroConexao e arquivo apagado', () async {
      final cliente = _cliente(
        _ClienteQueda(blocos.take(2).toList(), const SocketException('caiu')),
      );
      await expectLater(
        baixarAtualizacao(cliente, _info(conteudo), destino),
        throwsA(isA<ErroConexao>()),
      );
      naoSobraNada();
    });

    test('HTTP 404 vira ErroHttp e nada fica no disco', () async {
      final falso = ClienteFalso.fila([
        RespostaFalsa(404, texto: 'nada', motivo: 'Not Found'),
      ]);
      await expectLater(
        baixarAtualizacao(_cliente(falso), _info(conteudo), destino),
        throwsA(
          isA<ErroHttp>().having(
            (e) => e.toString(),
            'mensagem',
            '404 Client Error: Not Found for url: ${_info(conteudo).url}',
          ),
        ),
      );
      expect(falso.abortados, 1);
      naoSobraNada();
    });

    test('falha não remove um destino que já existia', () async {
      destino.writeAsBytesSync([1, 2, 3]);
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await expectLater(
        baixarAtualizacao(
          _cliente(falso),
          _info(conteudo, sha: _sha(utf8.encode('outro'))),
          destino,
        ),
        throwsA(isA<ErroAtualizacao>()),
      );
      expect(destino.readAsBytesSync(), [1, 2, 3]);
      expect(pasta.listSync(), hasLength(1));
    });

    test('limpeza que falha não esconde o erro original', () async {
      // O parcial é uma pasta não vazia: abrir falha (erro de escrita) e
      // apagar também falha.
      final bloqueio = Directory('${destino.path}.tmp')..createSync();
      File('${bloqueio.path}/x').writeAsBytesSync([1]);
      final falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await expectLater(
        baixarAtualizacao(_cliente(falso), _info(conteudo), destino),
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.toString(),
            'mensagem',
            contains('gravar a atualização no disco'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(falso.abortados, 1);
    });
  });
}
