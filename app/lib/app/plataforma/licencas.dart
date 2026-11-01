// Licença da fonte Roboto (SIL OFL 1.1), embutida no app, na tela de licenças.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// O texto só é lido quando a tela de licenças pede; registrar não espera
/// disco nem pode falhar a abertura do app.
void registrarLicencaRoboto([AssetBundle? pacote]) {
  LicenseRegistry.addLicense(() async* {
    final texto = await (pacote ?? rootBundle).loadString(
      'assets/fonts/LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks(['Roboto'], texto);
  });
}
