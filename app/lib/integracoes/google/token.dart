import 'dart:convert';

import 'package:http/http.dart' as pkg;

import '../../nucleo/ambiente.dart';
import '../../nucleo/armazenamento.dart';
import '../../nucleo/compat/numeros.dart';
import '../../nucleo/erros.dart';
import '../http/cliente.dart';
import 'constantes.dart';
import 'erros.dart';

const arquivoToken = 'token.json';

/// Segundos antes do vencimento em que o google-auth já considera vencido.
const margemRenovacao = 225;

const _msgLogin = 'Faça login com o Google.';
const _msgSessao = 'Sessão expirada. Faça login novamente.';
const _tokenUriPadrao = 'https://oauth2.googleapis.com/token';

String _dois(int n) => n.toString().padLeft(2, '0');

/// `datetime.isoformat() + "Z"` (microssegundos só se diferentes de zero).
String _isoExpiry(DateTime d) {
  final u = d.toUtc();
  final base =
      '${u.year.toString().padLeft(4, '0')}-${_dois(u.month)}-${_dois(u.day)}'
      'T${_dois(u.hour)}:${_dois(u.minute)}:${_dois(u.second)}';
  final micro = u.millisecond * 1000 + u.microsecond;
  return '$base${micro == 0 ? '' : '.${micro.toString().padLeft(6, '0')}'}Z';
}

/// `rstrip("Z").split(".")[0]` + `%Y-%m-%dT%H:%M:%S`, em UTC.
DateTime _lerExpiry(String texto) {
  final t = texto.replaceAll(RegExp(r'Z+$'), '').split('.')[0];
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$')
      .firstMatch(t);
  if (m == null) throw FormatException('expiry inválido: $texto');
  final n = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  return DateTime.utc(n[0], n[1], n[2], n[3], n[4], n[5]);
}

/// Credenciais no formato `authorized_user` do google-auth.
class TokenGoogle {
  TokenGoogle({
    this.token,
    this.refreshToken,
    this.tokenUri = _tokenUriPadrao,
    required this.clientId,
    required this.clientSecret,
    List<String>? scopes,
    this.expiry,
    this.universeDomain = 'googleapis.com',
    this.account = '',
  }) : scopes = scopes ?? List.of(escoposGoogle);

  /// `Credentials.from_authorized_user_info`; qualquer defeito vira
  /// [LoginNecessario].
  factory TokenGoogle.fromJson(Map<String, Object?> json) {
    try {
      final refresh = json['refresh_token'];
      final id = json['client_id'];
      final segredo = json['client_secret'];
      if (refresh is! String ||
          refresh.isEmpty ||
          id is! String ||
          id.isEmpty ||
          segredo is! String ||
          segredo.isEmpty) {
        throw const FormatException('campos obrigatórios ausentes');
      }
      final escopos = json['scopes'];
      final expiry = json['expiry'];
      final token = json['token'];
      final universo = json['universe_domain'];
      final conta = json['account'];
      return TokenGoogle(
        token: token is String ? token : null,
        refreshToken: refresh,
        // o google-auth ignora o token_uri do arquivo: não enviar segredos
        // a um host de arquivo adulterado
        tokenUri: _tokenUriPadrao,
        clientId: id,
        clientSecret: segredo,
        scopes: escopos is List
            ? escopos.map((e) => e as String).toList()
            : escopos is String
            ? escopos.split(' ').where((e) => e.isNotEmpty).toList()
            : null,
        // sem expiry nasce vencido e é renovado (credentials.py:503-504)
        expiry: expiry is String && expiry.isNotEmpty
            ? _lerExpiry(expiry)
            : DateTime.fromMicrosecondsSinceEpoch(
                arredondar(
                  (ambiente.agora() - margemRenovacao) * 1000000,
                  0,
                ).toInt(),
                isUtc: true,
              ),
        universeDomain: universo is String ? universo : 'googleapis.com',
        account: conta is String ? conta : '',
      );
    } catch (_) {
      throw LoginNecessario(_msgLogin);
    }
  }

  String? token;
  String? refreshToken;
  String tokenUri;
  String clientId;
  String clientSecret;
  List<String> scopes;
  DateTime? expiry;
  String universeDomain;
  String account;

  /// Chaves na ordem do `Credentials.to_json`, sem nulos.
  Map<String, Object?> toJson() => {
    if (token != null) 'token': token,
    if (refreshToken != null) 'refresh_token': refreshToken,
    'token_uri': tokenUri,
    'client_id': clientId,
    'client_secret': clientSecret,
    'scopes': scopes,
    'universe_domain': universeDomain,
    'account': account,
    if (expiry != null) 'expiry': _isoExpiry(expiry!),
  };

  /// `Credentials.valid`: há token e não falta menos de [margemRenovacao] s.
  bool valido(double agora) {
    if (token == null) return false;
    final e = expiry;
    if (e == null) return true;
    return agora < e.microsecondsSinceEpoch / 1000000 - margemRenovacao;
  }
}

/// `null` sem arquivo; JSON inválido → [LoginNecessario].
TokenGoogle? lerToken(Armazenamento a) {
  final texto = a.ler(arquivoToken);
  if (texto == null) return null;
  try {
    return TokenGoogle.fromJson(jsonDecode(texto) as Map<String, Object?>);
  } catch (_) {
    throw LoginNecessario(_msgLogin);
  }
}

void gravarToken(Armazenamento a, TokenGoogle t) =>
    a.gravar(arquivoToken, jsonEncode(t.toJson()));

/// google_sync.py:121-128: renova com o `refresh_token`; devolve o token novo.
Future<TokenGoogle> renovarToken(ClienteHttp http, TokenGoogle t) async {
  final refresh = t.refreshToken;
  if (refresh == null || refresh.isEmpty) throw LoginNecessario(_msgSessao);
  final pkg.Response resposta;
  try {
    resposta = await http.enviar(
      'POST',
      Uri.parse(t.tokenUri),
      corpo: {
        'grant_type': 'refresh_token',
        'client_id': t.clientId,
        'client_secret': t.clientSecret,
        'refresh_token': refresh,
        'scope': escoposGoogle.join(' '),
      },
    );
  } on ErroConexao catch (e) {
    throw Offline(e.mensagem);
  }
  final status = resposta.statusCode;
  if (status == 429 || status >= 500) {
    throw Offline(
      'O Google não respondeu (HTTP $status). Tente de novo mais tarde.',
    );
  }
  if (status != 200) throw LoginNecessario(_msgSessao);
  final Map<String, Object?> dados;
  try {
    dados = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, Object?>;
  } catch (_) {
    throw LoginNecessario(_msgSessao);
  }
  final novo = dados['access_token'];
  if (novo is! String) throw LoginNecessario(_msgSessao);
  final dura = dados['expires_in'];
  final novoRefresh = dados['refresh_token'];
  return TokenGoogle(
    token: novo,
    refreshToken: novoRefresh is String && novoRefresh.isNotEmpty
        ? novoRefresh
        : refresh,
    tokenUri: t.tokenUri,
    clientId: t.clientId,
    clientSecret: t.clientSecret,
    scopes: t.scopes,
    expiry: dura is num
        ? DateTime.fromMicrosecondsSinceEpoch(
            arredondar((ambiente.agora() + dura) * 1000000, 0).toInt(),
            isUtc: true,
          )
        : null,
    universeDomain: t.universeDomain,
    account: t.account,
  );
}
