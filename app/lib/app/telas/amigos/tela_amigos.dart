// Amigos: compartilhar a planilha, remover o acesso e ver os dados de um
// amigo (calculadora_darf.py:2922-2932, 3721-3839; android/main.py:2112-2187).
// Diálogo de 480 px no PC e tela cheia no celular. A validação do e-mail e a
// conta do compartilhamento ficam no serviço; aqui só se lê o campo e se
// mostra o resultado. A conta dona da pasta de relatórios também a
// compartilha com os amigos (o "Permitir" pede o escopo `drive`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart' hide Selo;
import '../../componentes/controles.dart';
import '../../componentes/carregando.dart';
import '../../componentes/dialogos.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';

const larguraDialogoAmigos = 480.0;

const textoSemConta = 'Conecte sua conta Google para adicionar amigos.';
const textoSemPlanilha =
    'Aguarde a criação da sua planilha no Google Drive e tente novamente.';
const textoExplicacao =
    'Ao adicionar um amigo, sua planilha é compartilhada com ele somente '
    'para leitura. Para ver os dados dele, ele também precisa adicionar você.';
const textoPermitirCompartilhamento =
    'Para compartilhar a pasta de relatórios automaticamente com seus amigos, '
    'entre de novo com o Google e permita o acesso ao Drive.';

/// Abre os amigos. Sem conta ou sem planilha só avisa (py:2922-2928); "Ver"
/// fecha a janela e troca a visão (py:2929-2932), sem mudar de aba no PC.
Future<void> abrirAmigos(BuildContext c) async {
  final estado = c.read<EstadoApp>();
  final conta = estado.conta;
  if (conta.email == null) {
    await avisar(c, 'Amigos', textoSemConta);
    return;
  }
  if (conta.linkPlanilha == null) {
    await avisar(c, 'Amigos', textoSemPlanilha);
    return;
  }
  final grande = expandido(c);
  final String? ver;
  if (grande) {
    ver = await showDialog<String>(
      context: c,
      builder: (_) => const Dialog(child: TelaAmigos(dialogo: true)),
    );
  } else {
    ver = await Navigator.of(c).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const TelaAmigos(dialogo: false),
      ),
    );
  }
  if (ver == null) return;
  await verAmigo(estado, ver, compacto: !grande);
}

/// Mostra os dados do amigo. O celular os mostra na Apuração, vindo de
/// Notícias, Relatórios ou Conta (android/main.py:2181); o PC só troca a
/// visão (py:2929-2931).
Future<void> verAmigo(
  EstadoApp estado,
  String email, {
  required bool compacto,
}) async {
  const semDadosDoAmigo = {Aba.noticias, Aba.relatorios, Aba.conta};
  if (compacto && semDadosDoAmigo.contains(estado.aba)) {
    estado.irPara(Aba.apuracao);
  }
  await estado.trocarVisao(email);
}

enum _Tom { neutro, ok, erro }

class ControleAmigos extends ChangeNotifier {
  ControleAmigos(this._servicos, this._estado) {
    _versao = _estado.versaoDados;
    _estado.addListener(_aoMudarEstado);
    unawaited(recarregar());
    unawaited(_reconciliar());
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late int _versao;
  int _geracao = 0;
  bool _descartado = false;

  /// Null até a primeira leitura; numa releitura que falha a anterior fica.
  List<Amigo>? amigos;
  String? erro;

  /// Compartilhar ou remover em andamento: desabilita as ações.
  bool ocupado = false;
  String status = '';
  _Tom _tom = _Tom.neutro;

  /// Só a conta dona da pasta de relatórios sai de `naoDono`.
  EstadoCompartilhamento compartilhamento = EstadoCompartilhamento.naoDono;

  /// O que aconteceu no último compartilhamento da pasta; vazio, nada.
  String statusRelatorios = '';
  _Tom _tomRelatorios = _Tom.neutro;

  /// "Permitir" em andamento.
  bool permitindo = false;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    _estado.removeListener(_aoMudarEstado);
    super.dispose();
  }

  void _aoMudarEstado() {
    if (_estado.versaoDados == _versao) return;
    _versao = _estado.versaoDados;
    unawaited(recarregar());
  }

  Future<void> recarregar() async {
    final geracao = ++_geracao;
    try {
      final lista = await _servicos.amigos();
      if (geracao != _geracao) return;
      amigos = lista;
      erro = null;
    } catch (e) {
      if (geracao != _geracao) return;
      erro = textoErro(e);
    }
    notifyListeners();
  }

  void _dizer(String texto, _Tom tom) {
    status = texto;
    _tom = tom;
  }

  /// Ao abrir e depois do "Permitir": confere o dono e compartilha a pasta
  /// com os amigos que faltam; falhas ficam em silêncio.
  Future<void> _reconciliar() async {
    try {
      compartilhamento = await _servicos.estadoCompartilhamento();
      notifyListeners();
      if (compartilhamento != EstadoCompartilhamento.pronto) return;
      _mostrarRelatorios(
        await _servicos.compartilharRelatorios(),
        adicao: false,
      );
    } catch (_) {
      // sem internet ou sem conta: nada a dizer
    }
    notifyListeners();
  }

  /// Só a adição avisa uma falha geral (rede, 403); e-mails recusados
  /// aparecem sempre; sem escopo, só o aviso "Permitir".
  void _mostrarRelatorios(ResultadoCompartilhamento r, {required bool adicao}) {
    if (r.semEscopo) compartilhamento = EstadoCompartilhamento.semEscopo;
    final erro = adicao && !r.semEscopo ? r.erro : null;
    statusRelatorios = [
      if (r.compartilhados > 0)
        'Pasta de relatórios compartilhada com ${r.compartilhados} amigo(s)',
      if (r.recusados.isNotEmpty)
        'A pasta de relatórios não foi compartilhada com '
            '${r.recusados.join(', ')}: e-mail sem conta Google.',
      if (erro != null)
        'Amigo adicionado, mas a pasta de relatórios não foi compartilhada: '
            '$erro',
    ].join('\n');
    _tomRelatorios = r.recusados.isNotEmpty || erro != null
        ? _Tom.erro
        : _Tom.ok;
  }

  /// Depois de salvar o amigo; a falha não desfaz a adição.
  Future<void> _compartilharAposAdicionar() async {
    try {
      _mostrarRelatorios(
        await _servicos.compartilharRelatorios(),
        adicao: true,
      );
    } catch (e) {
      // só a dona conferida (com o escopo) vê a falha
      if (compartilhamento != EstadoCompartilhamento.pronto) return;
      _mostrarRelatorios(
        ResultadoCompartilhamento(erro: textoErro(e)),
        adicao: true,
      );
    }
  }

  /// Entra de novo com a mesma conta pedindo o escopo `drive` e compartilha.
  Future<void> permitir() async {
    if (permitindo) return;
    permitindo = true;
    notifyListeners();
    try {
      await _servicos.permitirCompartilhamento();
    } catch (e) {
      if (e is! PedidoSuperado) {
        _estado.avisar('Login não concluído', textoErro(e));
      }
      return;
    } finally {
      permitindo = false;
      notifyListeners();
    }
    await _reconciliar();
  }

  /// Devolve true quando compartilhou (o campo é limpo).
  Future<bool> adicionar(String digitado) async {
    if (ocupado) return false;
    final email = digitado.trim().toLowerCase();
    ocupado = true;
    _dizer('Compartilhando sua planilha…', _Tom.neutro);
    notifyListeners();
    try {
      await _servicos.adicionarAmigo(email);
      _dizer('Planilha compartilhada com $email.', _Tom.ok);
      ocupado = false;
      await recarregar();
      await _compartilharAposAdicionar();
      return true;
    } catch (e) {
      _dizer(textoErro(e), _Tom.erro);
      return false;
    } finally {
      ocupado = false;
      notifyListeners();
    }
  }

  Future<void> remover(BuildContext c, String email) async {
    if (ocupado) return;
    final sim = await confirmar(
      c,
      'Remover amigo',
      '$email deixará de ter acesso à sua planilha.',
      sim: 'Remover',
      perigo: true,
    );
    if (!sim || _descartado) return;
    ocupado = true;
    _dizer('Removendo acesso…', _Tom.neutro);
    notifyListeners();
    try {
      await _servicos.removerAmigo(email);
      _dizer('Acesso de $email removido.', _Tom.ok);
      ocupado = false;
      await recarregar();
      // o serviço limpa o amigo aberto; a visão acompanha (py:3818-3819)
      if (_estado.amigo == email) await _estado.trocarVisao(null);
    } catch (e) {
      _dizer(textoErro(e), _Tom.erro);
    } finally {
      ocupado = false;
      notifyListeners();
    }
  }
}

class TelaAmigos extends StatelessWidget {
  const TelaAmigos({super.key, required this.dialogo, this.embutido = false});

  final bool dialogo;

  /// Só o bloco, sem barra nem rolagem própria, dentro da aba Conta do
  /// celular; "Ver" troca a visão em vez de fechar a janela.
  final bool embutido;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleAmigos>(
      create: (c) => ControleAmigos(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: embutido
          ? const _Corpo(dialogo: false, embutido: true)
          : dialogo
          ? const SizedBox(
              key: ValueKey('amigos-dialogo'),
              width: larguraDialogoAmigos,
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                child: _Corpo(dialogo: true),
              ),
            )
          : Scaffold(
              appBar: AppBar(title: const Text('Amigos')),
              body: const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _Corpo(dialogo: false),
              ),
            ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.dialogo, this.embutido = false});

  final bool dialogo;
  final bool embutido;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _adicionar(ControleAmigos controle) async {
    if (await controle.adicionar(_email.text) && mounted) _email.clear();
  }

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleAmigos>();
    final cores = CoresApp.de(context);
    final Color corStatus = switch (controle._tom) {
      _Tom.neutro => cores.textoSuave,
      _Tom.ok => cores.alta,
      _Tom.erro => cores.queda,
    };
    final Color corRelatorios = switch (controle._tomRelatorios) {
      _Tom.neutro => cores.textoSuave,
      _Tom.ok => cores.alta,
      _Tom.erro => cores.queda,
    };
    final lista = _Lista(controle: controle, embutido: widget.embutido);
    return Column(
      mainAxisSize: widget.dialogo || widget.embutido
          ? MainAxisSize.min
          : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.dialogo)
          Text('Amigos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(textoExplicacao, style: TextStyle(color: cores.textoSuave)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Expanded(
              child: SizedBox(
                height: expandido(context) ? 40 : 48,
                child: TextField(
                  key: const ValueKey('amigos-email'),
                  controller: _email,
                  autofocus: widget.dialogo,
                  keyboardType: TextInputType.emailAddress,
                  textAlignVertical: TextAlignVertical.center,
                  // preenche a altura do botão ao lado
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: const InputDecoration(
                    hintText: 'email@gmail.com',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onSubmitted: (_) => unawaited(_adicionar(controle)),
                ),
              ),
            ),
            // no celular só o "+" roxo, como no Radar: o campo precisa da largura
            if (expandido(context))
              BotaoPrincipal(
                key: const ValueKey('amigos-adicionar'),
                icone: Icons.person_add,
                onPressed: controle.ocupado
                    ? null
                    : () => unawaited(_adicionar(controle)),
                rotulo: 'Adicionar',
              )
            else
              IconButton.filled(
                key: const ValueKey('amigos-adicionar'),
                tooltip: 'Adicionar',
                icon: const Icon(Icons.add),
                onPressed: controle.ocupado
                    ? null
                    : () => unawaited(_adicionar(controle)),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(48),
                  minimumSize: const Size.square(48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          controle.status,
          key: const ValueKey('amigos-status'),
          style: TextStyle(color: corStatus),
        ),
        const SizedBox(height: 8),
        if (controle.compartilhamento == EstadoCompartilhamento.semEscopo) ...[
          _AvisoPermitir(controle: controle),
          const SizedBox(height: 8),
        ],
        if (controle.statusRelatorios.isNotEmpty) ...[
          Text(
            controle.statusRelatorios,
            key: const ValueKey('amigos-relatorios-status'),
            style: TextStyle(color: corRelatorios),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.dialogo)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: lista,
          )
        else if (widget.embutido)
          lista
        else
          Expanded(child: lista),
        if (widget.dialogo) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Só para a conta dona da pasta de relatórios sem o escopo `drive`.
class _AvisoPermitir extends StatelessWidget {
  const _AvisoPermitir({required this.controle});

  final ControleAmigos controle;

  @override
  Widget build(BuildContext context) {
    return Cartao(
      key: const ValueKey('amigos-aviso-permitir'),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(textoPermitirCompartilhamento),
            Align(
              alignment: Alignment.centerRight,
              child: BotaoPrincipal(
                key: const ValueKey('amigos-permitir'),
                icone: Icons.lock_open,
                onPressed: controle.permitindo
                    ? null
                    : () => unawaited(controle.permitir()),
                rotulo: 'Permitir',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.controle, required this.embutido});

  final ControleAmigos controle;
  final bool embutido;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.de(context);
    final amigos = controle.amigos;
    if (amigos == null) {
      final erro = controle.erro;
      if (erro == null) return const Carregando();
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(erro, style: TextStyle(color: cores.queda)),
          BotaoSecundario(
            icone: Icons.refresh,
            onPressed: () => unawaited(controle.recarregar()),
            rotulo: 'Tentar de novo',
          ),
        ],
      );
    }
    if (amigos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'Nenhum amigo adicionado.',
            style: TextStyle(color: cores.textoSuave),
          ),
        ),
      );
    }
    final livre = !controle.ocupado;
    return ListView(
      shrinkWrap: true,
      physics: embutido ? const NeverScrollableScrollPhysics() : null,
      children: [
        for (final a in amigos)
          ListTile(
            contentPadding: embutido ? EdgeInsets.zero : null,
            title: Text(
              a.email,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Adicionado em ${fmtData(a.desde)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotaoSecundario(
                  key: ValueKey('amigo-ver-${a.email}'),
                  icone: Icons.visibility,
                  compacto: true,
                  onPressed: livre
                      ? () => embutido
                            ? unawaited(
                                verAmigo(
                                  context.read<EstadoApp>(),
                                  a.email,
                                  compacto: true,
                                ),
                              )
                            : Navigator.of(context).pop(a.email)
                      : null,
                  rotulo: 'Ver',
                ),
                BotaoIcone(
                  key: ValueKey('amigo-remover-${a.email}'),
                  icone: Icons.delete_outline,
                  tooltip: 'Remover',
                  destrutivo: true,
                  onPressed: livre
                      ? () => unawaited(controle.remover(context, a.email))
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
