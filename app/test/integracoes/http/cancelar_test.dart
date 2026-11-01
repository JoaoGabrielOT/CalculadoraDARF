import 'dart:async';
import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

void main() {
  // Servidor só no loopback: responde 404 com corpo longo que nunca termina e
  // avisa quando o cliente fecha o socket.
  test('cancelar() depois de um 404 fecha a conexão do servidor', () async {
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fechou = Completer<void>();
    servidor.listen((req) async {
      final socket = await req.response.detachSocket(writeHeaders: false);
      socket.add(
        'HTTP/1.1 404 Not Found\r\ncontent-length: 1000000\r\n\r\nabc'
            .codeUnits,
      );
      await socket.flush();
      socket.listen(
        (_) {},
        onError: (_) {},
        onDone: () {
          if (!fechou.isCompleted) fechou.complete();
        },
      );
    });
    try {
      final navegador = ClienteHttp(IOClient(HttpClient()));
      final r = await navegador.abrir(
        'GET',
        Uri.parse('http://127.0.0.1:${servidor.port}/x.jpg'),
      );
      expect(r.status, 404);
      await r.cancelar();
      await r.cancelar(); // repetir não quebra
      await fechou.future.timeout(const Duration(seconds: 5));
    } finally {
      await servidor.close(force: true);
    }
  });
}
