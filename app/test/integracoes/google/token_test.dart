import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoio/cliente_falso.dart';

const _escopos = [
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/drive.metadata.readonly',
  'https://www.googleapis.com/auth/spreadsheets.readonly',
];

Map<String, Object?> _exemplo({String expiry = '2026-10-20T22:40:00Z'}) => {
  'token': 'ya29.a',
  'refresh_token': '1//r',
  'token_uri': 'https://oauth2.googleapis.com/token',
  'client_id': 'c.apps.googleusercontent.com',
  'client_secret': 's',
  'scopes': _escopos,
  'universe_domain': 'googleapis.com',
  'account': '',
  'expiry': expiry,
};

TokenGoogle _token({String? refresh = '1//r'}) => TokenGoogle(
  token: 'velho',
  refreshToken: refresh,
  clientId: 'c.apps.googleusercontent.com',
  clientSecret: 's',
  expiry: DateTime.utc(2026, 10, 20),
);

ClienteHttp _http(ClienteFalso f) => ClienteHttp(f);

Matcher _login(String msg) =>
    throwsA(isA<LoginNecessario>().having((e) => e.mensagem, 'mensagem', msg));

void main() {
  tearDown(() => ambiente = Ambiente.sistema());

  test('lê o token.json do google-auth e regrava no mesmo formato', () {
    // O google-auth descarta os microssegundos ao ler (split("."))
    final texto = jsonEncode(_exemplo(expiry: '2026-10-20T22:40:00.123456Z'));
    final t = TokenGoogle.fromJson(jsonDecode(texto) as Map<String, Object?>);
    expect(t.token, 'ya29.a');
    expect(t.refreshToken, '1//r');
    expect(t.expiry, DateTime.utc(2026, 10, 20, 22, 40));
    expect(jsonEncode(t.toJson()), jsonEncode(_exemplo()));
    expect(t.toJson().keys.toList(), _exemplo().keys.toList());
    final a = ArmazenamentoMemoria();
    expect(lerToken(a), isNull);
    gravarToken(a, t);
    expect(a.ler(arquivoToken), jsonEncode(_exemplo()));
    expect(jsonEncode(lerToken(a)!.toJson()), jsonEncode(_exemplo()));
  });

  test(
    'expiry com microssegundos é gravado como AAAA-MM-DDTHH:MM:SS.ffffffZ',
    () {
      final t = _token()
        ..expiry = DateTime.utc(2026, 10, 20, 22, 40, 0, 123, 456);
      expect(t.toJson()['expiry'], '2026-10-20T22:40:00.123456Z');
    },
  );

  test('token da 1.12 sem universe_domain/account e com scopes em texto', () {
    final j = _exemplo()
      ..remove('universe_domain')
      ..remove('account')
      ..['scopes'] = _escopos.join(' ');
    final t = TokenGoogle.fromJson(j);
    expect(t.scopes, _escopos);
    expect(t.toJson()['universe_domain'], 'googleapis.com');
    expect(t.toJson()['account'], '');
  });

  test('universe_domain e account são preservados', () {
    final j = _exemplo()
      ..['universe_domain'] = 'outro.com'
      ..['account'] = 'a@b.c';
    final t = TokenGoogle.fromJson(j);
    expect(t.toJson()['universe_domain'], 'outro.com');
    expect(t.toJson()['account'], 'a@b.c');
  });

  test('expiry sem microssegundos e sem expiry', () {
    final t = TokenGoogle.fromJson(_exemplo());
    expect(t.expiry, DateTime.utc(2026, 10, 20, 22, 40));
    final j = _exemplo()..remove('expiry');
    final s = TokenGoogle.fromJson(j);
    expect(s.expiry, isNull);
    expect(s.valido(9e12), isTrue);
    expect(s.toJson().containsKey('expiry'), isFalse);
    s.token = null;
    expect(s.valido(0), isFalse);
    expect(s.toJson().containsKey('token'), isFalse);
  });

  test('sem refresh_token, client_id ou client_secret → LoginNecessario("Faça login com o Google.")', () {
    for (final k in ['refresh_token', 'client_id', 'client_secret']) {
      final j = _exemplo()..remove(k);
      expect(() => TokenGoogle.fromJson(j), _login('Faça login com o Google.'));
    }
  });

  test('JSON inválido → LoginNecessario("Faça login com o Google.")', () {
    for (final t in ['', '{', '[]', 'null']) {
      final a = ArmazenamentoMemoria()..gravar(arquivoToken, t);
      expect(() => lerToken(a), _login('Faça login com o Google.'), reason: t);
    }
    final a = ArmazenamentoMemoria()
      ..gravar(arquivoToken, jsonEncode(_exemplo(expiry: 'ontem')));
    expect(() => lerToken(a), _login('Faça login com o Google.'));
  });

  test('valido: faltando menos de 3 min 45 s conta como vencido', () {
    final t = TokenGoogle.fromJson(_exemplo());
    final e = t.expiry!.millisecondsSinceEpoch / 1000;
    expect(t.valido(e - 224), isFalse);
    expect(t.valido(e - 226), isTrue);
    expect(t.valido(e - 225), isFalse);
  });

  test('renovarToken: corpo do formulário e novo expiry', () async {
    ambiente = Ambiente.fixo(agora: 1761000000.0);
    final f = ClienteFalso.fila([
      RespostaFalsa(
        200,
        json: {
          'access_token': 'ya29.novo',
          'expires_in': 3599,
          'refresh_token': '1//novo',
        },
      ),
    ]);
    final t = await renovarToken(_http(f), _token());
    final p = f.pedidos.single;
    expect(p.metodo, 'POST');
    expect(p.url.toString(), 'https://oauth2.googleapis.com/token');
    expect(p.formulario, {
      'grant_type': 'refresh_token',
      'client_id': 'c.apps.googleusercontent.com',
      'client_secret': 's',
      'refresh_token': '1//r',
    });
    expect(t.token, 'ya29.novo');
    expect(t.refreshToken, '1//novo');
    expect(
      t.expiry,
      DateTime.fromMillisecondsSinceEpoch(
        (1761000000 + 3599) * 1000,
        isUtc: true,
      ),
    );
    expect(t.valido(1761000000.0), isTrue);
  });

  test(
    'renovarToken mantém o refresh_token antigo quando a resposta não traz',
    () async {
      final f = ClienteFalso.fila([
        RespostaFalsa(200, json: {'access_token': 'n', 'expires_in': 3599}),
      ]);
      final t = await renovarToken(_http(f), _token());
      expect(t.refreshToken, '1//r');
      expect(t.scopes, _escopos);
    },
  );

  test('renovarToken: 400 invalid_grant → LoginNecessario("Sessão expirada. Faça login novamente.")', () async {
    for (final s in [400, 401]) {
      final f = ClienteFalso.fila([
        RespostaFalsa(s, json: {'error': 'invalid_grant'}),
      ]);
      await expectLater(
        renovarToken(_http(f), _token()),
        _login('Sessão expirada. Faça login novamente.'),
      );
    }
    final f = ClienteFalso.fila([]);
    await expectLater(
      renovarToken(_http(f), _token(refresh: null)),
      _login('Sessão expirada. Faça login novamente.'),
    );
    expect(f.pedidos, isEmpty);
  });

  test('renovarToken: sem rede → Offline; 503 e 429 → Offline', () async {
    final sem = ClienteFalso.fila([
      RespostaFalsa(0, erro: const SocketException('sem rede')),
    ]);
    await expectLater(
      renovarToken(ClienteHttp(sem), _token()),
      throwsA(
        isA<Offline>().having(
          (e) => e.mensagem,
          'mensagem',
          contains('sem rede'),
        ),
      ),
    );
    for (final s in [503, 429]) {
      final f = ClienteFalso.fila([RespostaFalsa(s)]);
      await expectLater(
        renovarToken(_http(f), _token()),
        throwsA(
          isA<Offline>().having(
            (e) => e.mensagem,
            'mensagem',
            'O Google não respondeu (HTTP $s). Tente de novo mais tarde.',
          ),
        ),
      );
    }
  });
}
