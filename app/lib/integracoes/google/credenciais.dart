import 'dart:convert';

import 'erros.dart';

/// Cliente OAuth do `credentials.json` (google_sync.py:166-167).
class ClienteOAuth {
  ClienteOAuth._(this.clientId, this.clientSecret, this.authUri, this.tokenUri);

  /// Tira o BOM; usa `installed`, senão `web`, senão a raiz.
  factory ClienteOAuth.deTexto(String texto) {
    try {
      final sem = texto.startsWith('﻿') ? texto.substring(1) : texto;
      final raiz = jsonDecode(sem) as Map<String, Object?>;
      // `or` do Python: objeto vazio ou ausente passa para o próximo
      final dados =
          [raiz['installed'], raiz['web']]
              .whereType<Map<String, Object?>>()
              .where((m) => m.isNotEmpty)
              .firstOrNull ??
          raiz;
      final segredo = dados['client_secret'];
      return ClienteOAuth._(
        dados['client_id']! as String,
        segredo is String ? segredo : '',
        dados['auth_uri']! as String,
        dados['token_uri']! as String,
      );
    } catch (_) {
      throw SemCredencial('Arquivo credentials.json não encontrado.');
    }
  }

  final String clientId;
  final String clientSecret;
  final String authUri;
  final String tokenUri;
}
