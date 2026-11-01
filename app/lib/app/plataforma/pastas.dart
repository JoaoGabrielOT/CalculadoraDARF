// Pastas do app nas duas plataformas (layout da pasta `dados/` da 1.12).

import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<({String dados, String temporaria})> pastasDoApp() async {
  final suporte = await getApplicationSupportDirectory();
  final temporaria = await getTemporaryDirectory();
  return (
    dados: '${suporte.path}${Platform.pathSeparator}dados',
    temporaria: temporaria.path,
  );
}
