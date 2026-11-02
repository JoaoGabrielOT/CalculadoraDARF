// Ponto de corte entre o layout compacto (celular) e o expandido (PC). Folha:
// só importa Flutter, para telas e componentes usarem sem depender de app.dart.

import 'package:flutter/widgets.dart';

/// Largura lógica a partir da qual o app usa o layout de PC.
const larguraExpandida = 840.0;

bool expandido(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= larguraExpandida;
