// Pastas do app nas duas plataformas (layout da pasta `dados/` da 1.12).

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<({String dados, String temporaria})> pastasDoApp() async {
  final suporte = await getApplicationSupportDirectory();
  final temporaria = await getTemporaryDirectory();
  final dados = '${suporte.path}${Platform.pathSeparator}dados';
  // A pasta existe antes do primeiro uso (leituras, cache de logos, gravação).
  await Directory(dados).create(recursive: true);
  return (dados: dados, temporaria: temporaria.path);
}
