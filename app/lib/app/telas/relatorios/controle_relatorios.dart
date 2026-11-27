// Estado da aba Relatórios: a visão (cache e pasta do Drive), o relatório
// aberto e o que acontece ao entrar na aba e ao trocar de conta. A pasta é
// lida ao abrir a aba, no Atualizar e quando a conta muda; a resposta de um
// pedido antigo é descartada quando a de um mais novo já foi aplicada.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../integracoes/integracoes.dart';
import '../../../nucleo/nucleo.dart';
import '../../estado/estado_app.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';

class ControleRelatorios extends ChangeNotifier {
  ControleRelatorios(this._servicos, this._estado) {
    _naAba = _estado.aba == Aba.relatorios;
    _email = _estado.conta.email;
    _estado.addListener(_aoMudarEstado);
    unawaited(_pedirVisao(_servicos.relatorios));
    // fora do `build` em que o provedor cria o controle
    if (_naAba) scheduleMicrotask(() => unawaited(atualizar()));
  }

  final ServicosApp _servicos;
  final EstadoApp _estado;

  late bool _naAba;
  String? _email;
  int _geracao = 0;

  /// Geração da última visão aplicada; o cache (pedido antes do `atualizar`)
  /// ainda vale enquanto a pasta não responde.
  int _geracaoAplicada = 0;
  int _geracaoAbrir = 0;
  bool _descartado = false;

  /// Relatório que o usuário escolheu na lista; null = o da visão (o de hoje
  /// ou o mais recente).
  String? _escolhido;

  /// Relatório tocado na lista cuja abertura ainda não terminou (ela espera
  /// na fila do serviço o `atualizar` em curso).
  String? _pedido;

  /// null enquanto a primeira leitura não chega.
  VisaoRelatorios? visao;

  /// O relatório na tela e o nome do arquivo dele.
  Relatorio? aberto;
  String? nomeAberto;
  bool atualizando = false;

  /// Falha ao abrir ou atualizar; o que estava na tela continua à vista.
  String? erro;

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
    final naAba = _estado.aba == Aba.relatorios;
    final entrou = naAba && !_naAba;
    _naAba = naAba;
    final email = _estado.conta.email;
    final trocouConta = email != _email;
    _email = email;
    if (trocouConta) {
      // outra conta: nada do que estava aberto vale
      _escolhido = null;
      _pedido = null;
      _geracaoAbrir++;
    }
    if (entrou || trocouConta) unawaited(atualizar());
  }

  /// Lista a pasta de novo (e baixa o que mudou).
  Future<void> atualizar() async {
    atualizando = true;
    notifyListeners();
    await _pedirVisao(_servicos.atualizarRelatorios);
  }

  /// Uma leitura só é descartada se outra mais nova já foi aplicada; o erro
  /// vale só para a última pedida.
  Future<void> _pedirVisao(Future<VisaoRelatorios> Function() pedir) async {
    final geracao = ++_geracao;
    var aplicou = false;
    try {
      final nova = await pedir();
      if (geracao < _geracaoAplicada) return;
      _geracaoAplicada = geracao;
      aplicou = true;
      if (geracao == _geracao) erro = null;
      _aplicar(nova);
    } catch (e) {
      if (geracao != _geracao) return;
      if (e is! PedidoSuperado) erro = textoErro(e);
    } finally {
      if (geracao == _geracao) atualizando = false;
      if (aplicou || geracao == _geracao) notifyListeners();
    }
  }

  /// O escolhido continua aberto enquanto existir na pasta; senão vale o da
  /// visão.
  void _aplicar(VisaoRelatorios nova) {
    visao = nova;
    final padrao =
        nova.nomeAtual ??
        escolherRelatorio(nova.itens, nova.hoje).escolhido?.nome;
    // o tocado na lista vale como escolhido: a abertura dele vem depois
    final escolhido = _escolhido ?? _pedido;
    if (escolhido != null && nova.itens.any((i) => i.nome == escolhido)) {
      if (escolhido == _escolhido &&
          escolhido == padrao &&
          nova.atual != null) {
        aberto = nova.atual;
      }
      return;
    }
    _escolhido = null;
    _pedido = null;
    _geracaoAbrir++;
    nomeAberto = padrao;
    aberto = nova.atual;
    // o escolhido não está em cache: pede o conteúdo (sem conexão, o
    // download acabou de falhar)
    if (aberto == null &&
        padrao != null &&
        nova.situacao != SituacaoRelatorios.semConexao) {
      unawaited(_abrir(padrao, escolha: false));
    }
  }

  /// Abre um relatório da lista; se falhar, o anterior continua à vista. Sem
  /// o escopo da pasta, lista de novo, que mostra o "entrar de novo".
  Future<void> abrir(String nome) => _abrir(nome, escolha: true);

  Future<void> _abrir(String nome, {required bool escolha}) async {
    final geracao = ++_geracaoAbrir;
    if (escolha) _pedido = nome;
    try {
      final r = await _servicos.abrirRelatorio(nome);
      if (geracao != _geracaoAbrir) return;
      if (escolha) _escolhido = nome;
      nomeAberto = nome;
      aberto = r;
      erro = null;
    } catch (e) {
      if (geracao != _geracaoAbrir || e is PedidoSuperado) return;
      if (e is EscopoInsuficiente) {
        unawaited(atualizar());
        return;
      }
      erro = textoErro(e);
    } finally {
      if (geracao == _geracaoAbrir) _pedido = null;
    }
    notifyListeners();
  }

  /// O item da lista do relatório aberto.
  ResumoRelatorio? get itemAberto {
    for (final i in visao?.itens ?? const <ResumoRelatorio>[]) {
      if (i.nome == nomeAberto) return i;
    }
    return null;
  }

  /// Login de novo com o escopo da pasta, sem sair da conta.
  Future<void> entrarDeNovo() async {
    try {
      await _servicos.entrarDeNovoGoogle();
    } catch (e) {
      if (e is! PedidoSuperado) {
        _estado.avisar('Login não concluído', textoErro(e));
      }
      return;
    }
    await atualizar();
  }

  /// Sem conta: o login de sempre (o e-mail novo dispara o [atualizar]).
  Future<void> entrar() async {
    try {
      await _servicos.conectar();
    } catch (e) {
      if (e is! PedidoSuperado) {
        _estado.avisar('Login não concluído', textoErro(e));
      }
    }
  }

  void abrirLink(Uri uri) => unawaited(_estado.abrirLink(uri));
}
