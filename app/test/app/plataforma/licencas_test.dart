import 'dart:convert';

import 'package:calculadoradarf/app/plataforma/licencas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Pacote extends AssetBundle {
  final List<String> pedidos = [];

  @override
  Future<ByteData> load(String key) async {
    pedidos.add(key);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode('Licença X')));
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

void main() {
  test('a licença da Roboto entra no registro de licenças', () async {
    final pacote = _Pacote();
    registrarLicencaRoboto(pacote);
    final todas = await LicenseRegistry.licenses.toList();
    final roboto = todas.where((l) => l.packages.contains('Roboto')).toList();
    expect(roboto, hasLength(1));
    expect(
      roboto.single.paragraphs.map((p) => p.text).join(' '),
      contains('Licença X'),
    );
    expect(pacote.pedidos, ['assets/fonts/LICENSE.txt']);
  });
}
