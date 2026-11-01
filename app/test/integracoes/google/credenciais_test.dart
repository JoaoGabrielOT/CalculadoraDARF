import 'dart:convert';

import 'package:calculadoradarf/integracoes/google/credenciais.dart';
import 'package:calculadoradarf/integracoes/google/credenciais_asset.dart';
import 'package:calculadoradarf/integracoes/google/erros.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _dados =
    '{"client_id": "c.apps.googleusercontent.com", "client_secret": "s", '
    '"auth_uri": "https://accounts.google.com/o/oauth2/auth", '
    '"token_uri": "https://oauth2.googleapis.com/token"}';

class _PacoteFalso extends CachingAssetBundle {
  _PacoteFalso(this.arquivos);

  final Map<String, String> arquivos;

  @override
  Future<ByteData> load(String key) async {
    final t = arquivos[key];
    if (t == null) throw FlutterError('asset ausente: $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(t)));
  }
}

void main() {
  test('credenciais: installed, web, raiz e BOM', () {
    final i = ClienteOAuth.deTexto('{"installed": $_dados}');
    expect(i.clientId, 'c.apps.googleusercontent.com');
    expect(i.clientSecret, 's');
    expect(i.authUri, 'https://accounts.google.com/o/oauth2/auth');
    expect(i.tokenUri, 'https://oauth2.googleapis.com/token');
    expect(
      ClienteOAuth.deTexto('{"web": ${_dados.replaceAll('"s"', '"w"')}}')
          .clientSecret,
      'w',
    );
    expect(ClienteOAuth.deTexto(_dados).clientId, i.clientId);
    expect(
      ClienteOAuth.deTexto('﻿{"installed": $_dados}').clientId,
      i.clientId,
    );
    final semSegredo = _dados.replaceFirst('"client_secret": "s", ', '');
    expect(ClienteOAuth.deTexto(semSegredo).clientSecret, '');
  });

  test('credenciais ausentes ou inválidas → SemCredencial("Arquivo credentials.json não encontrado.")', () {
    for (final t in [
      '',
      'não é json',
      '[]',
      '{}',
      '{"installed": {"client_id": "x"}}',
    ]) {
      expect(
        () => ClienteOAuth.deTexto(t),
        throwsA(
          isA<SemCredencial>().having(
            (e) => e.mensagem,
            'mensagem',
            'Arquivo credentials.json não encontrado.',
          ),
        ),
        reason: t,
      );
    }
  });

  test(
    'carregarClienteOAuth lê do AssetBundle; asset ausente → SemCredencial',
    () async {
      final c = await carregarClienteOAuth(
        _PacoteFalso({caminhoCredenciais: '{"installed": $_dados}'}),
      );
      expect(c.clientId, 'c.apps.googleusercontent.com');
      expect(
        carregarClienteOAuth(_PacoteFalso({})),
        throwsA(
          isA<SemCredencial>().having(
            (e) => e.mensagem,
            'mensagem',
            'Arquivo credentials.json não encontrado.',
          ),
        ),
      );
    },
  );
}
