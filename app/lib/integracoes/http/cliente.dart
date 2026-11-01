import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../nucleo/erros.dart';
import 'semaforo.dart';

/// Espera injetada (nos testes não dorme de verdade).
typedef Esperar = Future<void> Function(Duration duracao);

/// Esperas entre as repetições após HTTP 429; a última se repete.
const esperas429 = [Duration(seconds: 2), Duration(seconds: 5)];

/// Teto da espera pedida por `Retry-After`.
const _tetoRetryAfter = Duration(seconds: 30);

/// Resposta com o corpo ainda em fluxo (downloads).
class RespostaContinua {
  RespostaContinua({
    required this.status,
    required this.motivo,
    required this.cabecalhos,
    required this.urlFinal,
    required Stream<List<int>> blocos,
    required void Function() abortar,
  }) : // Parâmetros nomeados não podem ser privados.
       // ignore: prefer_initializing_formals
       _blocos = blocos,
       // ignore: prefer_initializing_formals
       _abortar = abortar;

  final int status;
  final String? motivo;
  final Map<String, String> cabecalhos;
  final Uri urlFinal;
  final Stream<List<int>> _blocos;
  final void Function() _abortar;
  bool _entregue = false;

  /// Corpo em fluxo de assinatura única; quem o pega fica responsável por ele.
  Stream<List<int>> get blocos {
    _entregue = true;
    return _blocos;
  }

  /// Aborta o pedido e solta a conexão, sem ler o resto do corpo. Se ninguém
  /// pegou o [blocos], assina-o antes: sem ouvinte o abort só emitiria o erro
  /// e o socket continuaria aberto (io_client do pacote http).
  Future<void> cancelar() async {
    if (_entregue) {
      _abortar();
      return;
    }
    _entregue = true;
    final assinatura = _blocos.listen(null, onError: (Object _) {});
    _abortar();
    await assinatura.cancel();
  }
}

/// Falha de transporte vira [ErroConexao] com o texto original; o resto passa.
Object _converterErro(Object e) {
  if (e is ErroConexao) return e;
  if (e is TimeoutException ||
      e is SocketException ||
      e is http.ClientException ||
      e is HandshakeException ||
      e is TlsException ||
      e is HttpException) {
    return ErroConexao(e.toString());
  }
  return e;
}

/// Cliente HTTP das integrações: tempo limite, User-Agent, erros do núcleo,
/// repetição com espera em 429 e limite de concorrência. Não lança por status.
class ClienteHttp {
  ClienteHttp(
    this._cliente, {
    this.userAgent,
    this.cabecalhos = const {},
    this.tempoLimite = const Duration(seconds: 20),
    int? maxSimultaneas,
    this.repeticoes429 = 0,
    Esperar? esperar,
  }) : _semaforo = maxSimultaneas == null ? null : Semaforo(maxSimultaneas),
       _esperar = esperar ?? Future<void>.delayed;

  final http.Client _cliente;
  final String? userAgent;
  final Map<String, String> cabecalhos;
  final Duration tempoLimite;
  final int repeticoes429;
  final Semaforo? _semaforo;
  final Esperar _esperar;

  http.AbortableRequest _montar(
    String metodo,
    Uri url,
    Map<String, String>? extras,
    Object? corpo,
    Future<void> abortar,
  ) {
    final req = http.AbortableRequest(metodo, url, abortTrigger: abortar);
    if (userAgent != null) req.headers['User-Agent'] = userAgent!;
    req.headers.addAll(cabecalhos);
    if (extras != null) req.headers.addAll(extras);
    if (corpo is String) {
      req.body = corpo;
    } else if (corpo is Map<String, String>) {
      req.bodyFields = corpo;
    } else if (corpo is List<int>) {
      req.bodyBytes = corpo;
    } else if (corpo != null) {
      throw ArgumentError('corpo de tipo inesperado: ${corpo.runtimeType}');
    }
    return req;
  }

  Duration _espera429(int tentativa, Map<String, String> resposta) {
    final valor = resposta.entries
        .where((e) => e.key.toLowerCase() == 'retry-after')
        .map((e) => e.value)
        .firstOrNull;
    final segundos = int.tryParse((valor ?? '').trim());
    if (segundos != null) {
      final d = Duration(seconds: segundos < 0 ? 0 : segundos);
      return d > _tetoRetryAfter ? _tetoRetryAfter : d;
    }
    return esperas429[tentativa < esperas429.length
        ? tentativa
        : esperas429.length - 1];
  }

  Future<http.Response> _uma(
    String metodo,
    Uri url,
    Map<String, String>? extras,
    Object? corpo,
    Duration limite,
  ) async {
    final abortar = Completer<void>();
    try {
      final req = _montar(metodo, url, extras, corpo, abortar.future);
      return await (() async {
        final resposta = await _cliente.send(req);
        return http.Response.fromStream(resposta);
      })().timeout(limite);
    } catch (e) {
      if (!abortar.isCompleted) abortar.complete();
      throw _converterErro(e);
    }
  }

  /// Envia o pedido e lê o corpo inteiro. 429 repete até [repeticoes429]
  /// vezes e devolve a última resposta; o semáforo cobre as esperas.
  Future<http.Response> enviar(
    String metodo,
    Uri url, {
    Map<String, String>? cabecalhos,
    Object? corpo,
    Duration? tempoLimite,
  }) {
    Future<http.Response> executar() async {
      final limite = tempoLimite ?? this.tempoLimite;
      var tentativa = 0;
      while (true) {
        final r = await _uma(metodo, url, cabecalhos, corpo, limite);
        if (r.statusCode != 429 || tentativa >= repeticoes429) return r;
        await _esperar(_espera429(tentativa, r.headers));
        tentativa++;
      }
    }

    final semaforo = _semaforo;
    return semaforo == null ? executar() : semaforo.usar(executar);
  }

  /// Envia o pedido e devolve o corpo em fluxo; cada bloco respeita o tempo limite.
  Future<RespostaContinua> abrir(
    String metodo,
    Uri url, {
    Map<String, String>? cabecalhos,
    Duration? tempoLimite,
  }) async {
    final limite = tempoLimite ?? this.tempoLimite;
    final abortar = Completer<void>();
    void abortarAgora() {
      if (!abortar.isCompleted) abortar.complete();
    }

    final http.StreamedResponse resposta;
    try {
      final req = _montar(metodo, url, cabecalhos, null, abortar.future);
      resposta = await _cliente.send(req).timeout(limite);
    } catch (e) {
      abortarAgora();
      throw _converterErro(e);
    }
    final blocos = resposta.stream
        .timeout(
          limite,
          onTimeout: (sink) {
            abortarAgora();
            sink.addError(
              ErroConexao(TimeoutException(null, limite).toString()),
            );
            sink.close();
          },
        )
        .handleError((Object e) => throw _converterErro(e));
    return RespostaContinua(
      status: resposta.statusCode,
      motivo: resposta.reasonPhrase,
      cabecalhos: resposta.headers,
      urlFinal: resposta is http.BaseResponseWithUrl
          ? (resposta as http.BaseResponseWithUrl).url
          : url,
      blocos: blocos,
      abortar: abortarAgora,
    );
  }

  void fechar() => _cliente.close();
}
