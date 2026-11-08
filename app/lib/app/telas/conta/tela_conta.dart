// Aba Conta: Google, Amigos, Configurações e Sobre (android/main.py:2070-2111,
// 2249-2331, 2769-2777) e, no PC, o botão da conta do cabeçalho com o menu
// do Windows (calculadora_darf.py:2728-2827). O login, a sincronização e a
// conta ficam nos serviços; aqui só se pede a ação e se mostra o resultado.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../../versao.dart';
import '../../componentes/cartao.dart';
import '../../componentes/dialogos.dart';
import '../../estado/estado_app.dart';
import '../../plataforma/plataforma.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../../tema/tema_visual.dart';
import '../amigos/tela_amigos.dart';
import '../atualizacao/dialogo_atualizacao.dart';

const _larguraMaxima = 640.0;

const textoSemCredencialWindows =
    'Coloque o arquivo credentials.json na mesma pasta do programa '
    'ou gere o .exe com ele na pasta.';
const textoSemCredencialAndroid =
    'Credencial do Google não encontrada neste aplicativo.';

Color corSync(CoresApp cores, StatusSync s) => switch (s) {
  StatusSync.off || StatusSync.sync => cores.textoSuave,
  StatusSync.login || StatusSync.pendente || StatusSync.offline => cores.aviso,
  StatusSync.ok => cores.alta,
  StatusSync.erro => cores.queda,
};

/// Botão da conta do cabeçalho (PC): com conta abre o menu; sem credencial
/// avisa; senão conecta (py:2748-2764).
Future<void> clicarConta(BuildContext c) async {
  final estado = c.read<EstadoApp>();
  final conta = estado.conta;
  final controle = ControleConta(
    c.read<ServicosApp>(),
    estado,
    c.read<Plataforma>(),
  );
  try {
    if (conta.email == null) {
      await controle.conectar();
      return;
    }
    final info = StringBuffer('Planilha "$nomePlanilha" no seu Google Drive.');
    if (conta.ultimoErro.isNotEmpty) {
      info.write('\n\nÚltimo erro: ${conta.ultimoErro}');
    }
    final escolha = await showDialog<String>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(conta.email!),
        content: Text(info.toString()),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: CoresApp.de(ctx).queda,
            ),
            onPressed: () => Navigator.pop(ctx, 'sair'),
            child: const Text('Sair da conta'),
          ),
          OutlinedButton(
            onPressed: conta.linkPlanilha == null
                ? null
                : () => Navigator.pop(ctx, 'abrir'),
            child: const Text('Abrir planilha'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'sync'),
            child: const Text('Sincronizar agora'),
          ),
        ],
      ),
    );
    if (!c.mounted) return;
    switch (escolha) {
      case 'abrir':
        await controle.abrirPlanilha();
      case 'sync':
        await controle.sincronizarAgora();
      case 'sair':
        await controle.sair(c);
    }
  } finally {
    controle.dispose();
  }
}

class ControleConta extends ChangeNotifier {
  ControleConta(this._servicos, this._estado, this._plataforma);

  final ServicosApp _servicos;
  final EstadoApp _estado;
  final Plataforma _plataforma;

  bool _descartado = false;
  int _geracao = 0;

  /// `conectar` em andamento (dura até o fim do login).
  bool conectando = false;

  /// Sincronizar ou sair em andamento: desabilita as duas ações.
  bool agindo = false;

  bool verificando = false;

  /// Resultado da última verificação manual; vazio = nada a mostrar.
  String mensagemAtualizacao = '';

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }

  void _avisarErro(String titulo, Object e) =>
      _estado.avisar(titulo, textoErro(e));

  /// Sem credencial só avisa (py:2754-2757); o erro do login chega pelo
  /// serviço como aviso, e uma falha inesperada vira o mesmo aviso.
  Future<void> conectar() async {
    if (conectando) return;
    if (!_estado.conta.temCredencial) {
      _estado.avisar(
        'Credencial não encontrada',
        _plataforma.windows
            ? textoSemCredencialWindows
            : textoSemCredencialAndroid,
      );
      return;
    }
    conectando = true;
    notifyListeners();
    try {
      await _servicos.conectar();
    } catch (e) {
      _avisarErro('Login não concluído', e);
    } finally {
      conectando = false;
      notifyListeners();
    }
  }

  Future<void> cancelarLogin() async {
    try {
      await _servicos.cancelarLogin();
    } catch (e) {
      _avisarErro('Não foi possível cancelar', e);
    }
  }

  Future<void> sincronizarAgora() async {
    if (agindo) return;
    agindo = true;
    notifyListeners();
    try {
      await _servicos.sincronizarAgora();
    } catch (e) {
      _avisarErro('Não foi possível sincronizar', e);
    } finally {
      agindo = false;
      notifyListeners();
    }
  }

  Future<void> abrirPlanilha() async {
    final link = _estado.conta.linkPlanilha;
    if (link == null) return;
    await _estado.abrirLink(Uri.parse(link));
  }

  Future<void> sair(BuildContext c) async {
    if (agindo) return;
    final computador = _plataforma.windows ? 'computador' : 'aparelho';
    final sim = await confirmar(
      c,
      'Sair da conta',
      'Os dados continuam salvos neste $computador e na planilha.',
      sim: 'Sair',
      perigo: true,
    );
    if (!sim || _descartado) return;
    agindo = true;
    notifyListeners();
    try {
      await _servicos.sair();
    } catch (e) {
      _avisarErro('Não foi possível sair', e);
    } finally {
      agindo = false;
      notifyListeners();
    }
  }

  /// Verificação manual (android/main.py:2769-2777): sem versão nova e erro
  /// viram uma mensagem sob o botão; com versão nova oferece a atualização.
  Future<void> verificarAtualizacao(BuildContext c) async {
    if (verificando) return;
    final geracao = ++_geracao;
    verificando = true;
    mensagemAtualizacao = '';
    notifyListeners();
    InfoAtualizacao? info;
    String mensagem = '';
    try {
      info = await _servicos.verificarAtualizacao();
      if (info == null) {
        mensagem = 'Você já está na versão mais recente ($versaoApp).';
      }
    } catch (_) {
      mensagem = 'Não foi possível verificar atualizações.';
    }
    if (geracao != _geracao) return;
    verificando = false;
    mensagemAtualizacao = mensagem;
    notifyListeners();
    if (info != null && c.mounted) await oferecerAtualizacao(c, info);
  }
}

class TelaConta extends StatelessWidget {
  const TelaConta({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleConta>(
      create: (c) => ControleConta(
        c.read<ServicosApp>(),
        c.read<EstadoApp>(),
        c.read<Plataforma>(),
      ),
      child: const _Corpo(),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo();

  @override
  Widget build(BuildContext context) {
    final conta = context.select<EstadoApp, EstadoConta>((e) => e.conta);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _larguraMaxima),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              const _Rotulo('Google'),
              _BlocoGoogle(conta: conta),
              if (conta.email != null) ...[
                const SizedBox(height: 8),
                const _Rotulo('Amigos'),
                const _BlocoAmigos(),
              ],
              const SizedBox(height: 8),
              const _Rotulo('Configurações'),
              const _BlocoConfiguracoes(),
              const SizedBox(height: 8),
              const _Rotulo('Sobre'),
              const _BlocoSobre(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: CoresApp.de(context).textoSuave,
    ),
  );
}

class _BlocoGoogle extends StatelessWidget {
  const _BlocoGoogle({required this.conta});

  final EstadoConta conta;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    final controle = context.watch<ControleConta>();
    final status = Text(
      textoStatusSync(conta),
      style: TextStyle(fontSize: 12, color: corSync(cores, conta.status)),
    );
    if (conta.email == null) {
      final login = conta.status == StatusSync.login;
      final livre = !conta.ocupado && !controle.conectando && !login;
      return Cartao(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Text(
              'Conecte para sincronizar com a planilha no Google Drive e '
              'para compartilhar com amigos.',
              style: TextStyle(color: cores.textoSuave),
            ),
            status,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  onPressed: livre
                      ? () => unawaited(controle.conectar())
                      : null,
                  label: const Text('Conectar Google'),
                ),
                if (login)
                  OutlinedButton(
                    onPressed: () => unawaited(controle.cancelarLogin()),
                    child: const Text('Cancelar login'),
                  ),
              ],
            ),
            Text(
              'Depois de autorizar no navegador, volte para este app.',
              style: TextStyle(fontSize: 12, color: cores.textoSuave),
            ),
          ],
        ),
      );
    }
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            conta.email!,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          status,
          if (conta.status == StatusSync.erro && conta.ultimoErro.isNotEmpty)
            Text(
              'Último erro: ${conta.ultimoErro}',
              style: TextStyle(fontSize: 12, color: cores.queda),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.sync),
                onPressed: controle.agindo
                    ? null
                    : () => unawaited(controle.sincronizarAgora()),
                label: const Text('Sincronizar agora'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new),
                onPressed: conta.linkPlanilha == null
                    ? null
                    : () => unawaited(controle.abrirPlanilha()),
                label: const Text('Abrir planilha'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.logout),
                onPressed: controle.agindo
                    ? null
                    : () => unawaited(controle.sair(context)),
                label: const Text('Sair'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// No celular o bloco fica na própria aba; no PC os amigos abrem no
/// diálogo de sempre.
class _BlocoAmigos extends StatelessWidget {
  const _BlocoAmigos();

  @override
  Widget build(BuildContext context) {
    if (!expandido(context)) {
      return const Cartao(child: TelaAmigos(dialogo: false, embutido: true));
    }
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            textoExplicacao,
            style: TextStyle(color: CoresApp.de(context).textoSuave),
          ),
          OutlinedButton.icon(
            key: const ValueKey('conta-abrir-amigos'),
            icon: const Icon(Icons.group),
            onPressed: () => unawaited(abrirAmigos(context)),
            label: const Text('Abrir amigos'),
          ),
        ],
      ),
    );
  }
}

class _BlocoConfiguracoes extends StatelessWidget {
  const _BlocoConfiguracoes();

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    final prefs = estado.preferencias;
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const Text('Tema', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in TemaVisual.values)
                ChoiceChip(
                  key: ValueKey('tema-${t.chave}'),
                  label: Text(t.rotulo),
                  selected: prefs.tema == t,
                  onSelected: (_) => unawaited(estado.trocarTema(t)),
                ),
            ],
          ),
          Row(
            children: [
              const Expanded(child: Text('Notificar notícias relevantes')),
              Switch(
                key: const ValueKey('conta-notificar'),
                value: prefs.notificarNoticias,
                onChanged: (v) => unawaited(estado.definirNotificar(v)),
              ),
            ],
          ),
          const _PrejuizoInicial(),
        ],
      ),
    );
  }
}

const textoPrejuizoFechado =
    'O mês de corte já foi fechado; o prejuízo inicial não pode mais ser '
    'alterado.';

/// Prejuízo acumulado antes do mês de corte do custo médio (D4): sem corte
/// não aparece; só se edita com o mês de corte aberto.
class _PrejuizoInicial extends StatefulWidget {
  const _PrejuizoInicial();

  @override
  State<_PrejuizoInicial> createState() => _PrejuizoInicialState();
}

class _PrejuizoInicialState extends State<_PrejuizoInicial> {
  final _comum = TextEditingController();
  final _dayTrade = TextEditingController();
  PrejuizoInicial? _dados;
  // último texto posto pelo app em cada campo: se o campo difere, o usuário
  // está editando e uma recarga não o sobrescreve
  String _baseComum = '';
  String _baseDayTrade = '';
  int _versao = -1;
  int _pedido = 0;
  bool _salvando = false;
  String _erro = '';
  String _ok = '';

  @override
  void dispose() {
    _comum.dispose();
    _dayTrade.dispose();
    super.dispose();
  }

  Future<void> _carregar(ServicosApp servicos) async {
    final pedido = ++_pedido;
    PrejuizoInicial? dados;
    try {
      dados = await servicos.prejuizoInicial();
    } catch (_) {
      // sem leitura (mês ilegível): o campo some e o aviso fica na apuração
    }
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _dados = dados?.mesCorte == null ? null : dados;
      if (dados != null) _mostrar(dados.comum, dados.dayTrade);
    });
  }

  void _mostrar(double comum, double dayTrade) {
    if (_comum.text == _baseComum) _comum.text = precoTexto(comum);
    if (_dayTrade.text == _baseDayTrade) _dayTrade.text = precoTexto(dayTrade);
    _baseComum = precoTexto(comum);
    _baseDayTrade = precoTexto(dayTrade);
  }

  Future<void> _salvar(ServicosApp servicos) async {
    if (_salvando) return;
    final double comum;
    final double dayTrade;
    try {
      // "+ 0.0" troca -0.0 por 0.0
      comum = (_comum.text.trim().isEmpty ? 0 : parseValor(_comum.text)) + 0.0;
      dayTrade =
          (_dayTrade.text.trim().isEmpty ? 0 : parseValor(_dayTrade.text)) +
          0.0;
    } on FormatException {
      setState(() {
        _erro = 'Valor inválido.';
        _ok = '';
      });
      return;
    }
    setState(() {
      _salvando = true;
      _erro = '';
      _ok = '';
    });
    try {
      await servicos.definirPrejuizoInicial(comum, dayTrade);
      if (mounted) {
        setState(() {
          // o que foi salvo substitui o digitado (formato normalizado)
          _comum.text = _baseComum = precoTexto(comum);
          _dayTrade.text = _baseDayTrade = precoTexto(dayTrade);
          _ok = 'Prejuízo inicial salvo.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = textoErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicos = context.read<ServicosApp>();
    final versao = context.select<EstadoApp, int>((e) => e.versaoDados);
    if (versao != _versao) {
      _versao = versao;
      unawaited(_carregar(servicos));
    }
    final dados = _dados;
    if (dados == null) return const SizedBox.shrink();
    final cores = CoresApp.de(context);
    final editavel = dados.editavel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        const Divider(),
        Text(
          'Prejuízo acumulado antes de ${fmtMes(dados.mesCorte!)} '
          '(para compensar no imposto)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Row(
          spacing: 8,
          children: [
            for (final (chave, rotulo, c) in [
              ('prejuizo-comum', 'Operações comuns', _comum),
              ('prejuizo-dt', 'Day trade', _dayTrade),
            ])
              Expanded(
                child: TextField(
                  key: ValueKey(chave),
                  controller: c,
                  enabled: editavel,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: rotulo,
                    prefixText: 'R\$ ',
                  ),
                ),
              ),
          ],
        ),
        if (editavel)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const ValueKey('prejuizo-salvar'),
              onPressed: _salvando ? null : () => unawaited(_salvar(servicos)),
              child: const Text('Salvar prejuízo'),
            ),
          )
        else
          Text(
            textoPrejuizoFechado,
            style: TextStyle(fontSize: 12, color: cores.textoSuave),
          ),
        if (_erro.isNotEmpty)
          Text(_erro, style: TextStyle(fontSize: 12, color: cores.queda)),
        if (_ok.isNotEmpty)
          Text(_ok, style: TextStyle(fontSize: 12, color: cores.alta)),
      ],
    );
  }
}

class _BlocoSobre extends StatelessWidget {
  const _BlocoSobre();

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    final controle = context.watch<ControleConta>();
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const Text(
            'Calculadora DARF',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text('Versão $versaoApp', style: TextStyle(color: cores.textoSuave)),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.system_update),
              onPressed: controle.verificando
                  ? null
                  : () => unawaited(controle.verificarAtualizacao(context)),
              label: const Text('Verificar atualização'),
            ),
          ),
          if (controle.mensagemAtualizacao.isNotEmpty)
            Text(
              controle.mensagemAtualizacao,
              style: TextStyle(fontSize: 12, color: cores.textoSuave),
            ),
        ],
      ),
    );
  }
}
