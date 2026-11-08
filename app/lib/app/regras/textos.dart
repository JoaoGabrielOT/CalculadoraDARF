// Textos que a interface mostra para estados e erros (sem Flutter nem IO).

import 'dart:async';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../servicos/api.dart';
import '../servicos/servicos_isolate.dart'
    show ErroRemoto, msgServicosEncerrados;
import 'filtros.dart' show agruparVendas;

const textoServicosEncerrados =
    'Os serviços do app foram encerrados. Feche e abra o app de novo.';

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
  if (e is StateError && e.message == msgServicosEncerrados) {
    return textoServicosEncerrados;
  }
  // PlatformException (flutter/services) e ProcessException (dart:io) não
  // podem ser importadas aqui: reconhecidas pelo nome do tipo.
  final plataforma = switch (nome) {
    'PlatformException' => _primeiroTexto([
      _campo(() => (e as dynamic).message),
      _campo(() => (e as dynamic).code),
    ]),
    'ProcessException' => _textoProcesso(e),
    _ => null,
  };
  if (plataforma != null && plataforma.isNotEmpty) {
    return semPrefixoException(plataforma);
  }
  return 'Erro inesperado: $nome';
}

String? _primeiroTexto(List<String?> opcoes) {
  for (final o in opcoes) {
    if (o != null && o.isNotEmpty) return o;
  }
  return null;
}

String? _campo(Object? Function() ler) {
  try {
    return ler()?.toString();
  } catch (_) {
    return null;
  }
}

String? _textoProcesso(Object e) {
  final exe = _campo(() => (e as dynamic).executable);
  final msg = _campo(() => (e as dynamic).message);
  if (exe == null || exe.isEmpty) return msg;
  return msg == null || msg.isEmpty
      ? 'Não foi possível executar $exe.'
      : 'Não foi possível executar $exe: $msg';
}

/// O motivo de uma falha de inicialização: o texto de [textoErro] e, quando o
/// erro é inesperado, a mensagem da própria exceção (sem "Exception:").
String textoFalha(Object e) {
  final t = textoErro(e);
  if (!t.startsWith('Erro inesperado: ')) return t;
  // Exception('x') mostra só "x"; um Error (bug) mantém o cabeçalho.
  if (e is Exception) return semPrefixoException(e.toString());
  return '$t (${e.toString()})';
}

/// Subtexto do cartão da DARF (calculadora_darf.py:1587-1592).
String textoInfoDarf(Apuracao r, String mes) => infoDarf(r, mes);

/// "N venda(s) no mês" (py:1584); a venda em várias compras conta uma vez,
/// como na lista de vendas.
String textoVendasNoMes(Apuracao r) {
  final n = agruparVendas(r.ops).length;
  return '$n venda${n != 1 ? 's' : ''} no mês';
}

/// Subtexto do cartão do imposto (py:1586).
String textoIrrfRetido(Apuracao r) => 'IRRF já retido: ${brl(r.irrf)}';

/// Texto do limite de isenção (py:1596), com dois espaços ao redor do "de".
String textoLimiteIsencao(Apuracao r) =>
    '${brl(r.vendasAcoesSt)}  de  ${brl(limiteIsencao)}';

/// Situação da isenção de swing trade de ações (py:1598-1603).
String textoIsencao(Apuracao r) => r.isento
    ? 'Isento de IR em swing trade de ações'
    : 'Acima do limite · lucro tributado em 15%';

/// Avisos de um relatório de metas num diálogo só (título, texto); null se
/// não há nada a avisar. Executadas, inválidas e avisos manuais, nessa ordem
/// (calculadora_darf.py:2625-2637). Com um só título o diálogo leva o título
/// do Windows; com vários, "Metas" e cada trecho sob o seu título.
(String, String)? avisoRelatorioMetas(RelatorioMetas r) {
  final itens = <(String, String)>[];
  for (final m in r.executadas) {
    final ex = m.execucao ?? const <String, Object?>{};
    final stop = gatilho(m) == 'stop';
    final preco = (ex['preco_usado'] as num?)?.toDouble() ?? 0;
    itens.add((
      stop ? 'Stop atingido' : 'Meta atingida',
      '${m.ticker}: venda de ${m.qtd} a ${brl(preco)} registrada em '
          '${fmtData('${ex['data'] ?? ''}')} ${ex['hora'] ?? ''}.'
          '\n\n${ex['motivo'] ?? ''}${stop ? '\n$avisoGap' : ''}'
          '\n\n$avisoRegistro.',
    ));
  }
  for (final m in r.invalidas) {
    itens.add(('Meta inválida', '${m.ticker}: ${m.ultimoErro ?? ''}'));
  }
  for (final texto in r.avisos) {
    itens.add(('Ajuste manual necessário', texto));
  }
  if (itens.isEmpty) return null;
  final titulos = {for (final (t, _) in itens) t};
  if (titulos.length == 1) {
    return (titulos.single, [for (final (_, x) in itens) x].join('\n\n'));
  }
  return ('Metas', [for (final (t, x) in itens) '$t\n$x'].join('\n\n'));
}
