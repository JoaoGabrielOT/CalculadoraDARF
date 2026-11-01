// Parâmetros enviados ao isolate de serviços: só valores enviáveis e funções
// de nível superior. Sem package:flutter.

import 'package:http/http.dart' as http;

import '../../integracoes/integracoes.dart';
import 'api.dart';
import 'eventos.dart';
import 'servicos_isolate.dart';

class ParametrosServicos {
  const ParametrosServicos({
    required this.pastaDados,
    required this.pastaTemporaria,
    required this.windows,
    this.clienteOAuth,
    this.criarCliente = criarClienteReal,
    this.criarServicos = criarServicosLocais,
    this.timers = true,
  });

  /// `<getApplicationSupportDirectory()>/dados`.
  final String pastaDados;

  /// Destino dos downloads da atualização.
  final String pastaTemporaria;
  final bool windows;
  final ClienteOAuth? clienteOAuth;

  /// Cria o `http.Client` dentro do isolate (testes devolvem um `MockClient`).
  final http.Client Function() criarCliente;

  /// Monta os serviços dentro do isolate (testes usam o eco).
  final ServicosApp Function(
    ParametrosServicos p,
    AbrirUrl abrirUrl,
    void Function(EventoServico) emitir,
  )
  criarServicos;

  /// Liga os timers de sincronização, metas e notícias.
  final bool timers;
}
