import 'package:flutter/services.dart';

import 'credenciais.dart';
import 'erros.dart';

const caminhoCredenciais = 'assets/google/credentials.json';

/// Lê o `credentials.json` do asset; ausente → [SemCredencial].
Future<ClienteOAuth> carregarClienteOAuth([AssetBundle? pacote]) async {
  final String texto;
  try {
    texto = await (pacote ?? rootBundle).loadString(
      caminhoCredenciais,
      cache: false,
    );
  } catch (_) {
    throw SemCredencial('Arquivo credentials.json não encontrado.');
  }
  return ClienteOAuth.deTexto(texto);
}
