import 'dart:math';

import 'package:flutter/widgets.dart';

/// [m] com `padding` e `viewPadding` no maior valor, lado a lado, entre o que
/// já tem e [extra] (as áreas seguras lidas do navegador).
MediaQueryData comAreasSeguras(MediaQueryData m, EdgeInsets extra) {
  EdgeInsets maior(EdgeInsets a) => EdgeInsets.fromLTRB(
    max(a.left, extra.left),
    max(a.top, extra.top),
    max(a.right, extra.right),
    max(a.bottom, extra.bottom),
  );
  return m.copyWith(
    padding: maior(m.padding),
    viewPadding: maior(m.viewPadding),
  );
}
