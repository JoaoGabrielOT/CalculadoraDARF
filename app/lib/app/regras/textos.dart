// Textos que a interface mostra para estados e erros (sem Flutter nem IO).

import 'dart:async';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../servicos/api.dart';
import '../servicos/servicos_isolate.dart' show ErroRemoto;

/// Texto do status de sincronização (calculadora_darf.py:2715-2726); o
/// "Sincronizado" ganha " às HH:MM" quando há hora da última sincronização.
String textoStatusSync(EstadoConta c) {
  final texto = switch (c.status) {
    StatusSync.off => '○ Google não conectado',
    StatusSync.login => '◌ Aguardando login no navegador…',
    StatusSync.sync => '◌ Sincronizando…',
    StatusSync.ok => '● Sincronizado',
    StatusSync.pendente => '● Alterações pendentes',
    StatusSync.offline => '● Sem conexão · será enviado depois',
    StatusSync.erro => '● Erro ao sincronizar',
  };
  final ultima = c.ultimaSync;
  if (c.status == StatusSync.ok && ultima != null && ultima != 0) {
    return '$texto às ${horaMinuto(ultima)}';
  }
  return texto;
}

/// HH:MM, hora local, de um instante em segundos desde 1970.
String horaMinuto(double epoch) {
  final d = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round());
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// Tira o "Exception: " que o `toString()` de uma exceção qualquer põe na frente.
String semPrefixoException(String texto) =>
    texto.replaceFirst(RegExp(r'^Exception:\s*'), '');

/// O texto de um erro para o usuário, que nunca vê "Exception:".
String textoErro(Object e) {
  if (e is Offline) return 'Sem conexão com a internet.'; // py:3004
  final nome = e.runtimeType.toString();
  if (e is SemDados ||
      e is LimiteConsultas ||
      e is ErroConexao ||
      e is TimeoutException ||
      nome.contains('Socket') ||
      nome.contains('Connection') ||
      nome.contains('Timeout')) {
    return mensagemErro(e);
  }
  if (e is ErroNucleo) return semPrefixoException(e.toString());
  if (e is ErroRemoto) return semPrefixoException(e.mensagem);
  return 'Erro inesperado: $nome';
}
