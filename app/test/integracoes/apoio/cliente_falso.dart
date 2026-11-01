import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Pedido recebido pelo [ClienteFalso]; cabeçalhos com chaves em minúsculas.
class PedidoGravado {
  PedidoGravado(this.metodo, this.url, this.cabecalhos, this.corpo);

  final String metodo;
  final Uri url;
  final Map<String, String> cabecalhos;
  final List<int> corpo;

  String get texto => utf8.decode(corpo);

  Object? get json => jsonDecode(texto);

  Map<String, String> get formulario => Uri.splitQueryString(texto);
}

/// Resposta programada do [ClienteFalso]. [erro] é lançado no lugar da
/// resposta; [atraso] segura a resposta; [atrasoBlocos] segura cada bloco.
class RespostaFalsa {
  RespostaFalsa(
    this.status, {
    Object? json,
    String? texto,
    List<int>? bytes,
    List<List<int>>? blocos,
    Map<String, String> cabecalhos = const {},
    this.urlFinal,
    this.atraso = Duration.zero,
    this.atrasoBlocos = Duration.zero,
    this.erro,
    this.motivo,
  }) : cabecalhos = {
         if (json != null) 'content-type': 'application/json; charset=utf-8',
         if (json == null && texto != null)
           'content-type': 'text/plain; charset=utf-8',
         ...cabecalhos,
       },
       blocos =
           blocos ??
           [
             if (bytes != null)
               bytes
             else if (json != null)
               utf8.encode(jsonEncode(json))
             else if (texto != null)
               utf8.encode(texto),
           ];

  final int status;
  final List<List<int>> blocos;
  final Map<String, String> cabecalhos;
  final Uri? urlFinal;
  final Duration atraso;
  final Duration atrasoBlocos;
  final Object? erro;
  final String? motivo;
}

class _RespostaComUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _RespostaComUrl(
    super.stream,
    super.statusCode,
    this.url, {
    super.headers,
    super.reasonPhrase,
  });

  @override
  final Uri url;
}

/// Cliente HTTP dos testes: nenhuma rede, tudo gravado em [pedidos].
class ClienteFalso extends http.BaseClient {
  ClienteFalso(this._responder);

  ClienteFalso.fila(List<RespostaFalsa> respostas)
    : _responder = _daFila(List.of(respostas));

  final FutureOr<RespostaFalsa> Function(PedidoGravado) _responder;
  final List<PedidoGravado> pedidos = [];
  int _emAndamento = 0;
  int _maxSimultaneos = 0;

  /// Maior número de pedidos em andamento ao mesmo tempo.
  int get maxSimultaneos => _maxSimultaneos;

  static FutureOr<RespostaFalsa> Function(PedidoGravado) _daFila(
    List<RespostaFalsa> fila,
  ) {
    return (_) {
      if (fila.isEmpty) throw StateError('fila de respostas falsas esgotada');
      return fila.removeAt(0);
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final corpo = await request.finalize().toBytes();
    final cabecalhos = {
      for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
    };
    final pedido = PedidoGravado(
      request.method,
      request.url,
      cabecalhos,
      corpo,
    );
    pedidos.add(pedido);
    _emAndamento++;
    if (_emAndamento > _maxSimultaneos) _maxSimultaneos = _emAndamento;
    try {
      final resposta = await _responder(pedido);
      if (resposta.atraso > Duration.zero) {
        await Future<void>.delayed(resposta.atraso);
      }
      if (resposta.erro != null) throw resposta.erro!;
      Stream<List<int>> blocos() async* {
        for (final b in resposta.blocos) {
          if (resposta.atrasoBlocos > Duration.zero) {
            await Future<void>.delayed(resposta.atrasoBlocos);
          }
          yield b;
        }
      }

      final url = resposta.urlFinal;
      return url != null
          ? _RespostaComUrl(
              blocos(),
              resposta.status,
              url,
              headers: resposta.cabecalhos,
              reasonPhrase: resposta.motivo,
            )
          : http.StreamedResponse(
              blocos(),
              resposta.status,
              headers: resposta.cabecalhos,
              reasonPhrase: resposta.motivo,
            );
    } finally {
      _emAndamento--;
    }
  }
}
