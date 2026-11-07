import 'dart:io';

import 'package:flutter/services.dart';

/// Carrega Roboto (asset do app) e os ícones do Material (cache do SDK) para
/// que os testes de widget e os goldens desenhem texto e ícones reais, e não
/// os quadrados da fonte Ahem.
Future<void> carregarFontesDeTeste() async {
  final roboto = FontLoader('Roboto');
  for (final arquivo in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(_bytes(File('assets/fonts/$arquivo')));
  }
  await roboto.load();

  final raiz = Platform.environment['FLUTTER_ROOT'] ?? _raizDoFlutter();
  // No SDK o nome é 'materialicons-regular.otf' (minúsculas); procura sem
  // diferenciar maiúsculas para funcionar em Linux e Windows.
  final pasta = Directory('$raiz/bin/cache/artifacts/material_fonts');
  final otf = pasta.listSync().whereType<File>().firstWhere(
    (f) => f.uri.pathSegments.last.toLowerCase() == 'materialicons-regular.otf',
  );
  final icones = FontLoader('MaterialIcons')..addFont(_bytes(otf));
  await icones.load();

  // Reserva dos símbolos (● ▲ ▼ ⚠ ✓) do tema; o testador não procura fontes
  // do sistema sozinho. Só existe no Windows, onde os goldens rodam.
  final simbolos = _arquivoSimbolos();
  if (simbolos.existsSync()) {
    await (FontLoader('Segoe UI Symbol')..addFont(_bytes(simbolos))).load();
  }
}

File _arquivoSimbolos({String? windir}) => File(
  '${windir ?? Platform.environment['WINDIR'] ?? r'C:\Windows'}/Fonts/seguisym.ttf',
);

/// Motivo para pular os goldens quando falta a fonte dos símbolos (Linux,
/// CI): sem ela os 30 sairiam diferentes pixel a pixel. Null = rodar.
String? motivoParaPularGoldens({String? windir}) {
  final arquivo = _arquivoSimbolos(windir: windir);
  if (arquivo.existsSync()) return null;
  return 'Goldens só no Windows: falta ${arquivo.path} (Segoe UI Symbol).';
}

Future<ByteData> _bytes(File arquivo) async {
  final dados = await arquivo.readAsBytes();
  return ByteData.sublistView(dados);
}

/// `flutter_tester` já define FLUTTER_ROOT; se faltar, deduz do executável.
String _raizDoFlutter() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (File('${dir.path}/bin/flutter').existsSync() ||
        File('${dir.path}/bin/flutter.bat').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  throw StateError('FLUTTER_ROOT não encontrado');
}
