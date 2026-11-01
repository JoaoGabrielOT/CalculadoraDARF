import 'dart:io';

import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('cache_bin_'));
  tearDown(() => pasta.deleteSync(recursive: true));

  test('subpastas, modificadoEm e apagar', () async {
    final cache = CacheBinarioArquivos(pasta.path);
    expect(await cache.ler('logos/fontes/a.png'), isNull);
    expect(await cache.modificadoEm('logos/fontes/a.png'), isNull);

    final antes = DateTime.now().subtract(const Duration(seconds: 5));
    await cache.gravar('logos/fontes/a.png', [1, 2, 3]);
    expect(File('${pasta.path}/logos/fontes/a.png').existsSync(), isTrue);
    expect(await cache.ler('logos/fontes/a.png'), [1, 2, 3]);
    final quando = await cache.modificadoEm('logos/fontes/a.png');
    expect(quando!.isAfter(antes), isTrue);

    await cache.apagar('logos/fontes/a.png');
    expect(await cache.ler('logos/fontes/a.png'), isNull);
    await cache.apagar('logos/fontes/a.png'); // ausente não é erro
  });

  test('gravação substitui o arquivo inteiro', () async {
    final cache = CacheBinarioArquivos(pasta.path);
    await cache.gravar('x.bin', List.filled(100, 7));
    await cache.gravar('x.bin', [9]);
    expect(await cache.ler('x.bin'), [9]);
    final restos = pasta.listSync().map((e) => e.path).toList();
    expect(restos.where((p) => p.endsWith('.tmp')), isEmpty);
  });

  test('.tmp antigo é removido ao gravar; recente fica', () async {
    final cache = CacheBinarioArquivos(pasta.path);
    final velho = File('${pasta.path}/x.bin.abc.tmp')..writeAsBytesSync([1]);
    velho.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 2)),
    );
    final novo = File('${pasta.path}/x.bin.def.tmp')..writeAsBytesSync([1]);
    await cache.gravar('x.bin', [2]);
    expect(velho.existsSync(), isFalse);
    expect(novo.existsSync(), isTrue);
  });

  test('falha ao gravar relança o erro original e não deixa .tmp', () async {
    final cache = CacheBinarioArquivos(pasta.path);
    Directory('${pasta.path}/destino').createSync();
    // renomear um arquivo sobre uma pasta falha: o erro é o do rename
    await expectLater(
      cache.gravar('destino', [1]),
      throwsA(isA<FileSystemException>()),
    );
    final restos = pasta.listSync().map((e) => e.path).toList();
    expect(restos.where((p) => p.endsWith('.tmp')), isEmpty);
  });

  test('memória: relógio injetado, ler, apagar', () async {
    var agora = DateTime.utc(2026, 10, 28);
    final cache = CacheBinarioMemoria(relogio: () => agora);
    await cache.gravar('a/b', [1]);
    agora = DateTime.utc(2026, 10, 29);
    expect(await cache.modificadoEm('a/b'), DateTime.utc(2026, 10, 28));
    expect(await cache.ler('a/b'), [1]);
    await cache.apagar('a/b');
    expect(await cache.ler('a/b'), isNull);
    expect(await cache.modificadoEm('a/b'), isNull);
  });
}
