import 'dart:convert';
import 'dart:io';

import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/locais/atualizador_local.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/versao.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integracoes/apoio/cliente_falso.dart';

late Directory temp;
late ClienteFalso falso;
late List<EventoServico> eventos;

AtualizadorLocal montar({bool windows = true}) => AtualizadorLocal(
  http: ClienteHttp(falso),
  pastaTemporaria: temp.path,
  windows: windows,
  emitir: eventos.add,
);

InfoAtualizacao info(List<int> conteudo, {String versao = '99.0.0'}) =>
    InfoAtualizacao(
      versao: versao,
      notas: '',
      url: 'https://github.com/x/releases/download/v$versao/CalculadoraDARF',
      tamanho: conteudo.length,
      sha256: sha256.convert(conteudo).toString(),
    );

Map<String, Object?> release(String tag) => {
  'tag_name': tag,
  'body': 'notas',
  'draft': false,
  'prerelease': false,
  'assets': [
    for (final n in [nomeAssetWindows, nomeAssetAndroid])
      {
        'name': n,
        'browser_download_url': 'https://github.com/x/$n',
        'size': 10,
        'digest': 'sha256:abc',
      },
  ],
};

void main() {
  setUp(() {
    temp = Directory.systemTemp.createTempSync('atualizador_local_test');
    eventos = [];
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('verificarAtualizacao', () {
    for (final (windows, asset) in [
      (true, nomeAssetWindows),
      (false, nomeAssetAndroid),
    ]) {
      test('verificarAtualizacao usa o asset da plataforma '
          '(${windows ? 'Windows' : 'Android'})', () async {
        falso = ClienteFalso.fila([
          RespostaFalsa(200, json: release('v99.0.0')),
        ]);
        final r = await montar(windows: windows).verificarAtualizacao();
        expect(r!.versao, '99.0.0');
        expect(r.url, 'https://github.com/x/$asset');
      });
    }

    test('sem versão mais nova devolve null', () async {
      falso = ClienteFalso.fila([
        RespostaFalsa(200, json: release('v$versaoApp')),
      ]);
      expect(await montar().verificarAtualizacao(), isNull);
    });
  });

  group('baixarAtualizacao', () {
    test('devolve o caminho do File retornado, por plataforma', () async {
      final corpo = utf8.encode('instalador');
      for (final (windows, nome) in [
        (true, 'CalculadoraDARF-99.0.0.exe'),
        (false, 'CalculadoraDARF-99.0.0.apk'),
      ]) {
        falso = ClienteFalso.fila([RespostaFalsa(200, bytes: corpo)]);
        final caminho = await montar(windows: windows)
            .baixarAtualizacao(info(corpo));
        expect(caminho, '${temp.path}/$nome');
        expect(File(caminho).readAsBytesSync(), corpo);
      }
    });

    test('emite EventoProgresso no máximo a cada 300 ms e no fim', () async {
      final blocos = [for (var i = 0; i < 20; i++) List<int>.filled(100, i)];
      final tudo = [for (final b in blocos) ...b];
      falso = ClienteFalso.fila([RespostaFalsa(200, blocos: blocos)]);
      await montar().baixarAtualizacao(info(tudo));
      final p = eventos.whereType<EventoProgresso>().toList();
      expect(p.length, lessThan(5)); // blocos instantâneos: coalescidos
      expect(p.last.baixado, tudo.length);
      expect(p.last.total, tudo.length);
    });

    test('com blocos lentos o progresso espaça as emissões', () async {
      final blocos = [for (var i = 0; i < 5; i++) List<int>.filled(10, i)];
      final tudo = [for (final b in blocos) ...b];
      falso = ClienteFalso.fila([
        RespostaFalsa(
          200,
          blocos: blocos,
          atrasoBlocos: const Duration(milliseconds: 200),
        ),
      ]);
      await montar().baixarAtualizacao(info(tudo));
      final p = eventos.whereType<EventoProgresso>().toList();
      // 5 blocos em ~1 s: o primeiro, alguns intermediários e o final
      expect(p.length, inInclusiveRange(2, 5));
      expect(p.last.baixado, tudo.length);
      for (var i = 1; i < p.length; i++) {
        expect(p[i].baixado, greaterThan(p[i - 1].baixado));
      }
    });

    test("cancelarDownload faz o download lançar ErroAtualizacao('Atualização "
        "cancelada.')", () async {
      final blocos = [for (var i = 0; i < 10; i++) List<int>.filled(10, i)];
      final tudo = [for (final b in blocos) ...b];
      falso = ClienteFalso.fila([
        RespostaFalsa(
          200,
          blocos: blocos,
          atrasoBlocos: const Duration(milliseconds: 50),
        ),
      ]);
      final a = montar();
      final f = a.baixarAtualizacao(info(tudo));
      final erro = expectLater(
        f,
        throwsA(
          isA<ErroAtualizacao>().having(
            (e) => e.mensagem,
            'mensagem',
            'Atualização cancelada.',
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await a.cancelarDownload();
      await erro;
      expect(temp.listSync(), isEmpty);
    });

    test('um download novo não herda o cancelamento anterior', () async {
      final corpo = utf8.encode('instalador');
      falso = ClienteFalso.fila([RespostaFalsa(200, bytes: corpo)]);
      final a = montar();
      await a.cancelarDownload(); // sem download em curso
      final caminho = await a.baixarAtualizacao(info(corpo));
      expect(File(caminho).existsSync(), isTrue);
    });
  });
}
