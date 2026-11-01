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

/// google_sync.py:104-129 e 246-280: token, e-mail da conta e pedidos
/// autenticados com renovação automática.
class SessaoGoogle {
  SessaoGoogle({
    required this.http,
    required this.armazenamento,
    this.executar = executarEmIsolate,
  });

  final ClienteHttp http;
  final Armazenamento armazenamento;
  final Executar executar;
  TokenGoogle? _token;
  String? _email;

  /// Aumenta a cada `sair()`: o que estava em andamento antes não grava mais
  /// nem repõe token ou e-mail.
  int _geracao = 0;

  String? get email => _email;

  bool temToken() => armazenamento.existe(arquivoToken);

  /// Lê o `token.json`, renova se preciso (e grava) e abre a sessão.
  Future<String> carregarToken() async {
    final geracao = _geracao;
    var token = lerToken(armazenamento);
    if (token == null) throw LoginNecessario(_msgLogin);
    if (!token.valido(ambiente.agora())) {
      token = await renovarToken(http, token);
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

  Future<void> _renovar(int geracao) async {
    final atual = _token;
    if (atual == null || geracao != _geracao) throw LoginNecessario(_msgLogin);
    final novo = await renovarToken(http, atual);
    if (geracao != _geracao) throw LoginNecessario(_msgLogin);
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
    if (r.statusCode >= 400) throw ErroGoogle(_mensagem(r), r.statusCode);
    if (r.bodyBytes.isEmpty) return <String, Object?>{};
    try {
      return await decodificarJson(r.bodyBytes, executar)
          as Map<String, Object?>;
    } on FormatException {
      throw ErroGoogle(_msgInvalida);
    } on TypeError {
      throw ErroGoogle(_msgInvalida);
    }
  }

  String _mensagem(pkg.Response r) {
    try {
      final dados = jsonDecode(utf8.decode(r.bodyBytes));
      final erro = (dados as Map<String, Object?>)['error'];
      final msg = (erro as Map<String, Object?>)['message'];
      if (msg is String) return msg;
    } catch (_) {}
    final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
    return String.fromCharCodes(texto.runes.take(300));
  }
}
