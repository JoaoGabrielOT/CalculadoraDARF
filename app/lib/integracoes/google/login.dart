import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as pkg;

import '../../nucleo/ambiente.dart';
import '../../nucleo/compat/numeros.dart';
import '../../nucleo/erros.dart';
import '../http/cliente.dart';
import 'constantes.dart';
import 'credenciais.dart';
import 'erros.dart';
import 'sessao.dart';
import 'token.dart';

/// Abre a URL de autorização no navegador (no app, `url_launcher`).
typedef AbrirUrl = Future<void> Function(Uri url);

const _msgLogin = 'O login não foi concluído.';

/// google_sync.py:178-179.
const paginaLoginConcluido =
    "<html><body style='font-family:sans-serif;text-align:center;padding:48px'>"
    '<h2>Login concluído</h2><p>Volte para a Calculadora DARF.</p></body></html>';

/// `secrets.token_urlsafe(n)`: n bytes aleatórios em base64url sem `=`.
String _tokenUrlsafe(Random aleatorio, int bytes) => base64Url
    .encode([for (var i = 0; i < bytes; i++) aleatorio.nextInt(256)])
    .replaceAll('=', '');

/// `base64url(sha256(ascii(verificador)))` sem `=`.
String desafioPkce(String verificador) => base64Url
    .encode(sha256.convert(ascii.encode(verificador)).bytes)
    .replaceAll('=', '');

({String verificador, String desafio}) gerarPkce([Random? aleatorio]) {
  final verificador = _tokenUrlsafe(aleatorio ?? Random.secure(), 64);
  return (verificador: verificador, desafio: desafioPkce(verificador));
}

/// google_sync.py:197-200.
Uri urlAutorizacao(
  ClienteOAuth cliente, {
  required String redirect,
  required String desafio,
  required String estado,
}) => Uri.parse(cliente.authUri).replace(
  queryParameters: {
    'client_id': cliente.clientId,
    'redirect_uri': redirect,
    'response_type': 'code',
    'scope': escoposGoogle.join(' '),
    'access_type': 'offline',
    'prompt': 'consent',
    'code_challenge': desafio,
    'code_challenge_method': 'S256',
    'state': estado,
  },
);

/// Primeiro valor não vazio de [chave] (o `parse_qs` descarta vazios).
String? _valor(Map<String, List<String>> q, String chave) =>
    (q[chave] ?? const []).where((v) => v.isNotEmpty).firstOrNull;

/// google_sync.py:148-244: login com PKCE e servidor loopback; devolve o
/// e-mail da conta e deixa o `token.json` gravado.
Future<String> loginNavegador(
  SessaoGoogle sessao,
  ClienteOAuth cliente,
  ClienteHttp http,
  AbrirUrl abrirUrl, {
  Duration tempoLimite = const Duration(seconds: 600),
  Esperar? esperar,
}) async {
  final dormir = esperar ?? Future<void>.delayed;
  final pkce = gerarPkce();
  final estado = _tokenUrlsafe(Random.secure(), 16);
  final recebido = Completer<Uri>();
  final respondido = Completer<void>();
  HttpServer? servidor;

  final Uri retorno;
  final String redirect;
  try {
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirect = 'http://127.0.0.1:${servidor.port}/';
    servidor.listen((pedido) async {
      final uri = pedido.uri;
      final resposta = pedido.response;
      final ehRetorno =
          uri.toString().contains('code=') || uri.toString().contains('error=');
      // o código é guardado antes de responder (google_sync.py:172): o
      // navegador pode derrubar a conexão sem atrapalhar o login
      if (pedido.method == 'GET' && ehRetorno && !recebido.isCompleted) {
        recebido.complete(uri);
      }
      try {
        if (pedido.method != 'GET') {
          resposta.statusCode = HttpStatus.notImplemented;
        } else if (!ehRetorno) {
          resposta.statusCode = HttpStatus.notFound;
        } else {
          resposta.statusCode = HttpStatus.ok;
          resposta.headers.contentType = ContentType(
            'text',
            'html',
            charset: 'utf-8',
          );
          resposta.add(utf8.encode(paginaLoginConcluido));
        }
        await resposta.close();
      } catch (_) {
        // conexão do navegador interrompida
      } finally {
        if (ehRetorno && !respondido.isCompleted) respondido.complete();
      }
    });
    await abrirUrl(
      urlAutorizacao(
        cliente,
        redirect: redirect,
        desafio: pkce.desafio,
        estado: estado,
      ),
    );
    try {
      retorno = await recebido.future.timeout(tempoLimite);
    } on TimeoutException {
      throw ErroGoogle(_msgLogin);
    }
    // deixa a página de "Login concluído" sair antes de fechar o servidor
    await respondido.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  } finally {
    await servidor?.close(force: true);
  }

  final q = retorno.queryParametersAll;
  final erro = _valor(q, 'error');
  if (erro != null) {
    throw ErroGoogle(
      erro == 'access_denied'
          ? 'O login foi cancelado.'
          : 'O login não foi concluído: $erro',
    );
  }
  final codigo = _valor(q, 'code');
  if ((q['state'] ?? const ['']).first != estado || codigo == null) {
    throw ErroGoogle(_msgLogin);
  }

  // O Android bloqueia a rede de apps em segundo plano (o navegador está na
  // frente quando o Google redireciona): repete até o prazo.
  final prazo = ambiente.agora() + tempoLimite.inMicroseconds / 1000000;
  final resposta = await _trocarCodigo(
    http,
    cliente,
    codigo,
    redirect,
    pkce.verificador,
    prazo,
    dormir,
  );
  Map<String, Object?> tok = {};
  if (resposta.bodyBytes.isNotEmpty) {
    try {
      tok = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, Object?>;
    } catch (_) {}
  }
  final acesso = tok['access_token'];
  if (resposta.statusCode >= 400 || acesso is! String) {
    final detalhe = [
      tok['error_description'],
      tok['error'],
    ].where((v) => v != null && v != '' && v != false).firstOrNull;
    throw ErroGoogle(
      'O login não foi concluído: ${detalhe ?? resposta.statusCode}',
    );
  }
  final dura = tok['expires_in'];
  final segundos = dura is num
      ? dura.toInt()
      : dura is String
      ? int.tryParse(dura) ?? 3600
      : 3600;
  final refresh = tok['refresh_token'];
  final token = TokenGoogle(
    token: acesso,
    refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    tokenUri: cliente.tokenUri,
    clientId: cliente.clientId,
    clientSecret: cliente.clientSecret,
    scopes: List.of(escoposGoogle),
    expiry: DateTime.fromMicrosecondsSinceEpoch(
      arredondar((ambiente.agora() + segundos - 60) * 1000000, 0).toInt(),
      isUtc: true,
    ),
  );
  gravarToken(sessao.armazenamento, token);
  while (true) {
    try {
      return await sessao.iniciar(token);
    } on Offline {
      if (ambiente.agora() > prazo) rethrow;
      await dormir(const Duration(seconds: 2));
    }
  }
}

Future<pkg.Response> _trocarCodigo(
  ClienteHttp http,
  ClienteOAuth cliente,
  String codigo,
  String redirect,
  String verificador,
  double prazo,
  Esperar dormir,
) async {
  while (true) {
    try {
      return await http.enviar(
        'POST',
        Uri.parse(cliente.tokenUri),
        corpo: {
          'code': codigo,
          'client_id': cliente.clientId,
          'client_secret': cliente.clientSecret,
          'redirect_uri': redirect,
          'grant_type': 'authorization_code',
          'code_verifier': verificador,
        },
        tempoLimite: const Duration(seconds: 30),
      );
    } on ErroConexao catch (e) {
      if (ambiente.agora() > prazo) throw Offline(e.mensagem);
      await dormir(const Duration(seconds: 2));
    }
  }
}
