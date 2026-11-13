import 'package:http/http.dart' as http;

/// Para onde vão as URLs de sites livres (notícias): HTML ou imagem.
enum DestinoLivre { pagina, imagem }

/// Cabeçalho com que o servidor informa a URL final após redirecionamentos.
const cabecalhoUrlFinal = 'x-url-final';

/// Hosts que o navegador acessa direto, sem passar pelo servidor.
const hostsDiretos = {
  'sheets.googleapis.com',
  'www.googleapis.com',
  'oauth2.googleapis.com',
  'api.github.com',
};

/// Resposta com a URL final (o `StreamedResponseV2` do pacote http não é
/// exportado).
class _RespostaComUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _RespostaComUrl(
    super.stream,
    super.statusCode, {
    required this.url,
    super.contentLength,
    super.request,
    super.headers,
    super.isRedirect,
    super.persistentConnection,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

/// Cliente da versão Web: reescreve Yahoo e Google News (e sites livres) para
/// o servidor intermediário em [api]; os hosts diretos passam intactos.
class ClienteProxy extends http.BaseClient {
  ClienteProxy(
    this._interno, {
    required this.api,
    this.livre = DestinoLivre.pagina,
  });

  final http.Client _interno;
  final Uri api;
  final DestinoLivre livre;

  Uri reescrever(Uri url) {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw ArgumentError.value(url, 'url', 'esquema não suportado');
    }
    final base = api.toString();
    final texto = url.toString();
    if (texto == base ||
        texto.startsWith('$base/') ||
        texto.startsWith('$base?')) {
      return url;
    }
    if (hostsDiretos.contains(url.host)) return url;

    Uri destino(String caminho, [Map<String, String>? consulta]) => api.replace(
      path: '${api.path}/$caminho',
      queryParameters: consulta == null || consulta.isEmpty ? null : consulta,
    );

    const prefixoChart = '/v8/finance/chart/';
    if ((url.host == 'query1.finance.yahoo.com' ||
            url.host == 'query2.finance.yahoo.com') &&
        url.path.startsWith(prefixoChart)) {
      return destino(
        'yahoo/chart/${url.path.substring(prefixoChart.length)}',
        url.queryParameters,
      );
    }
    if (url.host == 'news.google.com') {
      if (url.path == '/rss/search') {
        return destino('noticias/rss', url.queryParameters);
      }
      if (url.path == '/_/DotsSplashUi/data/batchexecute') {
        return destino('noticias/resolver');
      }
      const prefixoArtigo = '/rss/articles/';
      if (url.path.startsWith(prefixoArtigo)) {
        return destino(
          'noticias/artigo/${url.path.substring(prefixoArtigo.length)}',
        );
      }
    }
    return destino(
      livre == DestinoLivre.imagem ? 'noticias/imagem' : 'noticias/pagina',
      {'url': texto},
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final destino = reescrever(request.url);
    final novo = http.AbortableRequest(
      request.method,
      destino,
      abortTrigger: request is http.Abortable ? request.abortTrigger : null,
    );
    request.headers.forEach((k, v) {
      if (k.toLowerCase() != 'user-agent') novo.headers[k] = v;
    });
    novo.followRedirects = request.followRedirects;
    novo.maxRedirects = request.maxRedirects;
    novo.persistentConnection = request.persistentConnection;
    novo.bodyBytes = await request.finalize().toBytes();

    final r = await _interno.send(novo);
    final urlFinal = r.headers[cabecalhoUrlFinal];
    return _RespostaComUrl(
      r.stream,
      r.statusCode,
      contentLength: r.contentLength,
      request: request,
      headers: r.headers,
      isRedirect: r.isRedirect,
      persistentConnection: r.persistentConnection,
      reasonPhrase: r.reasonPhrase,
      url: urlFinal == null ? request.url : Uri.parse(urlFinal),
    );
  }

  @override
  void close() => _interno.close();
}
