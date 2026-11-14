import 'dart:convert';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final api = Uri.parse('https://calculadora-darf-web.vercel.app/api');

Uri reescrever(String url, {DestinoLivre livre = DestinoLivre.pagina}) =>
    ClienteProxy(
      MockClient((_) async => http.Response('', 200)),
      api: api,
      livre: livre,
    ).reescrever(Uri.parse(url));

void main() {
  group('reescrever', () {
    test('Yahoo chart', () {
      final u = reescrever(
        'https://query1.finance.yahoo.com/v8/finance/chart/PETR4.SA?range=5d&interval=1d',
      );
      expect(u.host, 'calculadora-darf-web.vercel.app');
      expect(u.path, '/api/yahoo/chart/PETR4.SA');
      expect(u.queryParameters, {'range': '5d', 'interval': '1d'});
    });

    test('Google News RSS, resolver e artigo', () {
      final u = reescrever(
        'https://news.google.com/rss/search?q=PETR4&hl=pt-BR&gl=BR&ceid=BR:pt-419',
      );
      expect(u.path, '/api/noticias/rss');
      expect(u.queryParameters, {
        'q': 'PETR4',
        'hl': 'pt-BR',
        'gl': 'BR',
        'ceid': 'BR:pt-419',
      });
      expect(
        reescrever('https://news.google.com/_/DotsSplashUi/data/batchexecute'),
        Uri.parse('https://calculadora-darf-web.vercel.app/api/noticias/resolver'),
      );
      expect(
        reescrever('https://news.google.com/rss/articles/CBMiabc').path,
        '/api/noticias/artigo/CBMiabc',
      );
    });

    test('hosts diretos e URLs já na API ficam iguais', () {
      for (final s in [
        'https://sheets.googleapis.com/v4/spreadsheets/x',
        'https://www.googleapis.com/drive/v3/about',
        'https://calculadora-darf-web.vercel.app/api/yahoo/chart/X',
      ]) {
        expect(reescrever(s), Uri.parse(s));
      }
    });

    test('demais sites vão para página ou imagem', () {
      const orig = 'https://www.infomoney.com.br/a?b=1';
      final p = reescrever(orig);
      expect(p.path, '/api/noticias/pagina');
      expect(p.queryParameters['url'], orig);
      final i = reescrever(orig, livre: DestinoLivre.imagem);
      expect(i.path, '/api/noticias/imagem');
      expect(i.queryParameters['url'], orig);
    });

    test('esquema inválido', () {
      expect(() => reescrever('ftp://x/y'), throwsArgumentError);
    });
  });

  group('send', () {
    test('sem User-Agent, mantém cabeçalhos; urlFinal do cabeçalho', () async {
      late http.BaseRequest recebido;
      final interno = MockClient.streaming((req, bytes) async {
        recebido = req;
        await bytes.drain<void>();
        return http.StreamedResponse(
          Stream.value(utf8.encode('ok')),
          200,
          headers: {cabecalhoUrlFinal: 'https://site/final'},
        );
      });
      final c = ClienteHttp(
        ClienteProxy(interno, api: api),
        userAgent: 'Mozilla/5.0',
      );
      final r = await c.abrir(
        'GET',
        Uri.parse('https://www.infomoney.com.br/a'),
        cabecalhos: {'Accept-Language': 'pt-BR'},
      );
      await r.blocos.drain<void>();
      expect(
        recebido.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('user-agent')),
      );
      expect(recebido.headers['Accept-Language'], 'pt-BR');
      expect(recebido.url.path, '/api/noticias/pagina');
      expect(r.urlFinal, Uri.parse('https://site/final'));
    });

    test('Content-Type e corpo do POST são mantidos', () async {
      late String corpo;
      late String tipo;
      final interno = MockClient.streaming((req, bytes) async {
        corpo = utf8.decode(await bytes.expand((b) => b).toList());
        tipo = req.headers['content-type'] ?? '';
        return http.StreamedResponse(const Stream.empty(), 200);
      });
      final c = ClienteHttp(ClienteProxy(interno, api: api));
      await c.enviar(
        'POST',
        Uri.parse('https://news.google.com/_/DotsSplashUi/data/batchexecute'),
        cabecalhos: {'Content-Type': 'application/x-www-form-urlencoded'},
        corpo: 'a=b',
      );
      expect(corpo, 'a=b');
      expect(tipo, startsWith('application/x-www-form-urlencoded'));
    });

    test('sem cabeçalho, urlFinal é a original; 502 não lança', () async {
      final interno = MockClient.streaming(
        (req, bytes) async => http.StreamedResponse(const Stream.empty(), 502),
      );
      final c = ClienteHttp(ClienteProxy(interno, api: api));
      final original = Uri.parse('https://www.infomoney.com.br/a');
      final r = await c.abrir('GET', original);
      expect(r.status, 502);
      expect(r.urlFinal, original);
    });
  });
}
