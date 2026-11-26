import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as pkg;

import '../../nucleo/ambiente.dart';
import '../../nucleo/armazenamento.dart';
import '../../nucleo/compat/numeros.dart';
import '../../nucleo/erros.dart';
import '../http/cliente.dart';
import 'erros.dart';
import 'google.dart';
import 'guarda_nonce.dart';
import 'sessao.dart';
import 'token.dart';

/// `client_id` e `client_secret` do token da Web: quem guarda o segredo é o
/// servidor, e o `refresh_token` é o pacote cifrado que ele devolve.
const marcadorServidor = 'servidor';

const _msgLogin = 'O login não foi concluído.';
const _msgCancelado = 'O login foi cancelado.';
const _msgSessao = 'Sessão expirada. Faça login novamente.';
const _tituloAviso = 'Login não concluído';

final _formatoPacote = RegExp(r'^v1\.[A-Za-z0-9_-]{20,4096}$');

/// Grava o pacote no `token.json` sem `token` nem `expiry`: nasce vencido e a
/// primeira `carregarToken()` o renova pelo servidor.
void gravarPacoteWeb(Armazenamento a, String pacote) => gravarToken(
  a,
  TokenGoogle(
    refreshToken: pacote,
    clientId: marcadorServidor,
    clientSecret: marcadorServidor,
  ),
);

/// `$api/auth/inicio?volta=<origem>&n=<nonce>`.
Uri urlInicioLogin(Uri api, Uri origem, String nonce) =>
    Uri.parse('$api/auth/inicio')
        .replace(queryParameters: {'volta': origem.origin, 'n': nonce});

/// 32 bytes aleatórios em base64url sem `=` (43 caracteres).
String _gerarNonce() {
  final r = Random.secure();
  return base64Url
      .encode([for (var i = 0; i < 32; i++) r.nextInt(256)])
      .replaceAll('=', '');
}

/// Login da Web: guarda um nonce e sai da página rumo ao servidor. O futuro só
/// termina com erro; o resultado chega na volta, por [lerRetornoLogin].
FazerLogin criarLoginWeb({
  required Uri api,
  required Uri origem,
  required Future<void> Function(Uri url) irPara,
  required GuardaNonce nonces,
}) => (_, {Future<void>? cancelar}) async {
  final n = _gerarNonce();
  try {
    nonces.guardar(n);
    await irPara(urlInicioLogin(api, origem, n));
  } catch (_) {
    throw ErroGoogle(_msgLogin);
  }
  await (cancelar ?? Completer<void>().future);
  throw ErroGoogle(_msgCancelado);
};

/// Renova o token pelo servidor: `POST $api/auth/token` com o pacote.
RenovarToken criarRenovadorWeb(ClienteHttp http, Uri api) => (atual) async {
  final pacote = atual.refreshToken;
  if (pacote == null || pacote.isEmpty) throw LoginNecessario(_msgSessao);
  final pkg.Response resposta;
  try {
    resposta = await http.enviar(
      'POST',
      Uri.parse('$api/auth/token'),
      cabecalhos: {'Content-Type': 'application/json'},
      corpo: jsonEncode({'pacote': pacote}),
    );
  } on ErroConexao catch (e) {
    throw Offline(e.mensagem);
  }
  final status = resposta.statusCode;
  // só o 401 (pacote recusado) pede login de novo; o resto é falha passageira
  // e o token fica
  if (status == 401) throw LoginNecessario(_msgSessao);
  final indisponivel = Offline(
    'O servidor não respondeu (HTTP $status). Tente de novo mais tarde.',
  );
  if (status != 200) throw indisponivel;
  final Map<String, Object?> dados;
  try {
    dados = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, Object?>;
  } catch (_) {
    throw indisponivel;
  }
  final novo = dados['access_token'];
  if (novo is! String) throw indisponivel;
  final dura = dados['expires_in'];
  final novoPacote = dados['pacote'];
  return TokenGoogle(
    token: novo,
    refreshToken: novoPacote is String && novoPacote.isNotEmpty
        ? novoPacote
        : pacote,
    tokenUri: atual.tokenUri,
    clientId: atual.clientId,
    clientSecret: atual.clientSecret,
    scopes: escoposDaResposta(dados['scope']) ?? atual.scopes,
    expiry: dura is num
        ? DateTime.fromMicrosecondsSinceEpoch(
            arredondar((ambiente.agora() + dura) * 1000000, 0).toInt(),
            isUtc: true,
          )
        : null,
    universeDomain: atual.universeDomain,
    account: atual.account,
  );
};

/// Pede ao servidor que revogue o pacote; falhas são ignoradas (a sessão
/// local já foi apagada).
Future<void> revogarWeb(ClienteHttp http, Uri api, String pacote) async {
  try {
    await http.enviar(
      'POST',
      Uri.parse('$api/auth/sair'),
      cabecalhos: {'Content-Type': 'application/json'},
      corpo: jsonEncode({'pacote': pacote}),
    );
  } catch (_) {}
}

/// O que o servidor devolveu no fragmento do endereço.
sealed class RetornoLogin {}

final class RetornoPacote extends RetornoLogin {
  RetornoPacote(this.pacote);

  final String pacote;
}

final class RetornoErro extends RetornoLogin {
  RetornoErro(this.codigo);

  final String codigo;
}

bool _iguais(String a, String b) {
  if (a.length != b.length) return false;
  var dif = 0;
  for (var i = 0; i < a.length; i++) {
    dif |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return dif == 0;
}

/// Lê `#auth=<pacote>&n=<n>` ou `#auth_erro=<código>&n=<n>`; `null` se o
/// fragmento não for de login. O `n` tem de ser o nonce guardado na ida, ou
/// vira `RetornoErro('estado')`.
RetornoLogin? lerRetornoLogin(Uri endereco, {required String? nonceEsperado}) {
  final Map<String, String> q;
  try {
    q = Uri.splitQueryString(endereco.fragment);
  } catch (_) {
    return null;
  }
  final pacote = q['auth'];
  final erro = q['auth_erro'];
  if (pacote == null && erro == null) return null;
  final n = q['n'];
  if (n == null || nonceEsperado == null || !_iguais(n, nonceEsperado)) {
    return RetornoErro('estado');
  }
  if (erro != null) return RetornoErro(erro);
  if (!_formatoPacote.hasMatch(pacote!)) return RetornoErro('falhou');
  return RetornoPacote(pacote);
}

/// Título e texto do aviso para um retorno com erro.
(String, String) avisoRetorno(RetornoErro e) =>
    (_tituloAviso, e.codigo == 'acesso_negado' ? _msgCancelado : _msgLogin);
