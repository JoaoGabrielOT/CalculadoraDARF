import 'dart:convert';

import 'package:http/http.dart' as pkg;

import '../../nucleo/ambiente.dart';
import '../../nucleo/armazenamento.dart';
import '../../nucleo/erros.dart';
import '../executor.dart';
import '../http/cliente.dart';
import '../http/json.dart';
import 'constantes.dart';
import 'erros.dart';
import 'token.dart';

const _msgLogin = 'Faça login com o Google.';
const _msgSessao = 'Sessão expirada. Faça login novamente.';
const _msgInvalida = 'Resposta inválida do Google.';
const _msgNaN =
    'Há um valor inválido (NaN ou infinito) nos dados; nada foi enviado ao Google.';

/// Troca o token vencido por um novo (no app, [renovarToken]; na Web, pelo
/// servidor).
typedef RenovarToken = Future<TokenGoogle> Function(TokenGoogle atual);

/// google_sync.py:104-129 e 246-280: token, e-mail da conta e pedidos
/// autenticados com renovação automática.
class SessaoGoogle {
  SessaoGoogle({
    required this.http,
    required this.armazenamento,
    this.executar = executarEmIsolate,
    RenovarToken? renovar,
  }) : _renovarToken = renovar;

  final ClienteHttp http;
  final Armazenamento armazenamento;
  final Executar executar;
  final RenovarToken? _renovarToken;
  TokenGoogle? _token;
  String? _email;

  /// Aumenta a cada `sair()`: o que estava em andamento antes não grava mais
  /// nem repõe token ou e-mail.
  int _geracao = 0;

  String? get email => _email;

  /// Escopos do token em memória; `null` sem sessão.
  List<String>? get escopos {
    final t = _token;
    return t == null ? null : List.unmodifiable(t.scopes);
  }

  bool temToken() => armazenamento.existe(arquivoToken);

  /// Lê o `token.json`, renova se preciso (e grava) e abre a sessão.
  Future<String> carregarToken() async {
    final geracao = _geracao;
    var token = lerToken(armazenamento);
    if (token == null) throw LoginNecessario(_msgLogin);
    if (!token.valido(ambiente.agora())) {
      token = await _renovarCom(token);
      if (geracao != _geracao) throw LoginNecessario(_msgLogin);
      gravarToken(armazenamento, token);
    }
    return iniciar(token);
  }

  /// Guarda o token e descobre o e-mail da conta.
  Future<String> iniciar(TokenGoogle token) async {
    final geracao = _geracao;
    _token = token;
    final r = await req(
      'GET',
      '$urlDrive/about',
      params: {'fields': 'user(emailAddress)'},
    );
    if (geracao != _geracao) throw LoginNecessario(_msgLogin);
    final user = r['user'];
    final endereco = user is Map ? user['emailAddress'] : null;
    if (endereco is! String) {
      throw ErroGoogle('Resposta do Google sem o e-mail da conta.');
    }
    return _email = endereco.toLowerCase();
  }

  void sair() {
    _geracao++;
    _token = null;
    _email = null;
    try {
      armazenamento.apagar(arquivoToken);
    } catch (_) {
      // o estado em memória já foi zerado
    }
  }

  Uri _montarUrl(String url, Map<String, Object>? params) {
    final base = Uri.parse(url);
    if (params == null || params.isEmpty) return base;
    final consulta = <String, Object>{...base.queryParametersAll};
    for (final e in params.entries) {
      final v = e.value;
      consulta[e.key] = v is List ? [for (final i in v) '$i'] : '$v';
    }
    return base.replace(queryParameters: consulta);
  }

  Future<TokenGoogle> _renovarCom(TokenGoogle t) {
    final renovar = _renovarToken;
    return renovar == null ? renovarToken(http, t) : renovar(t);
  }

  Future<void> _renovar(int geracao) async {
    final atual = _token;
    if (atual == null || geracao != _geracao) throw LoginNecessario(_msgLogin);
    final novo = await _renovarCom(atual);
    if (geracao != _geracao) throw LoginNecessario(_msgLogin);
    // o refresh token pode vir rotacionado: sem gravar, a próxima carga
    // usaria o antigo
    try {
      gravarToken(armazenamento, novo);
    } catch (_) {
      // falha no disco não derruba o pedido: o token novo vale em memória
    }
    _token = novo;
  }

  /// `_req`: pedido autenticado; devolve o JSON da resposta (`{}` se vazia).
  Future<Map<String, Object?>> req(
    String metodo,
    String url, {
    Map<String, Object>? params,
    Object? json,
  }) async {
    if (_token == null) throw LoginNecessario(_msgLogin);
    final geracao = _geracao;
    // codifica antes de abrir conexão: NaN/Infinity não vai ao Google
    final String? corpo;
    try {
      corpo = json == null ? null : jsonEncode(json);
    } on JsonUnsupportedObjectError {
      throw ErroGoogle(_msgNaN);
    }
    final uri = _montarUrl(url, params);
    if (!_token!.valido(ambiente.agora())) await _renovar(geracao);

    Future<pkg.Response> enviar() async {
      final token = _token;
      if (token == null || geracao != _geracao) {
        throw LoginNecessario(_msgLogin);
      }
      try {
        return await http.enviar(
          metodo,
          uri,
          cabecalhos: {
            'Authorization': 'Bearer ${token.token}',
            if (corpo != null) 'Content-Type': 'application/json',
          },
          corpo: corpo,
          tempoLimite: const Duration(seconds: 30),
        );
      } on ErroConexao catch (e) {
        throw Offline(e.mensagem);
      }
    }

    var r = await enviar();
    if (r.statusCode == 401) {
      await _renovar(geracao);
      r = await enviar();
      if (r.statusCode == 401) throw LoginNecessario(_msgSessao);
    }
    if (r.statusCode >= 400) {
      final erro = _erroDoCorpo(r);
      if (r.statusCode == 403 && _faltaEscopo(erro)) {
        throw EscopoInsuficiente(_mensagem(r, erro), r.statusCode);
      }
      throw ErroGoogle(_mensagem(r, erro), r.statusCode);
    }
    if (r.bodyBytes.isEmpty) return <String, Object?>{};
    try {
      return await decodificarJson(r.bodyBytes, executar)
          as Map<String, Object?>;
    } on FormatException {
      throw RespostaInvalida(_msgInvalida);
    } on TypeError {
      throw RespostaInvalida(_msgInvalida);
    }
  }

  /// O objeto `error` do corpo JSON de um erro do Google, se houver.
  Map<String, Object?>? _erroDoCorpo(pkg.Response r) {
    try {
      final dados = jsonDecode(utf8.decode(r.bodyBytes));
      final erro = (dados as Map<String, Object?>)['error'];
      return erro as Map<String, Object?>;
    } catch (_) {
      return null;
    }
  }

  /// `errors[].reason` (v3) ou `details[].reason` (google.rpc.ErrorInfo).
  bool _faltaEscopo(Map<String, Object?>? erro) {
    bool tem(Object? lista, String motivo) =>
        lista is List && lista.any((i) => i is Map && i['reason'] == motivo);
    return erro != null &&
        (tem(erro['errors'], 'insufficientPermissions') ||
            tem(erro['details'], 'ACCESS_TOKEN_SCOPE_INSUFFICIENT'));
  }

  String _mensagem(pkg.Response r, Map<String, Object?>? erro) {
    final msg = erro?['message'];
    if (msg is String) return msg;
    final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
    return String.fromCharCodes(texto.runes.take(300));
  }
}
