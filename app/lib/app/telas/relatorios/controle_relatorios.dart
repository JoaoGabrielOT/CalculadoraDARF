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
    unawaited(_carregarCarteira());
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

  /// Tickers com posição aberta (`qtd > 0`) no mês atual; null enquanto não
  /// carregou ou se falhou (o filtro "Na minha carteira" some).
  Set<String>? carteira;

  /// Período da lista dos anteriores em dias; null = todos.
  int? periodoDias;

  void definirPeriodo(int? dias) {
    if (dias == periodoDias) return;
    periodoDias = dias;
    notifyListeners();
  }

  int _geracaoCarteira = 0;

  Future<void> _carregarCarteira() async {
    final geracao = ++_geracaoCarteira;
    Set<String>? nova;
    try {
      final v = await _servicos.posicoes(ambiente.hoje().substring(0, 7));
      nova = {
        for (final p in v.posicoes)
          if (p.qtd > 0) p.ticker,
      };
    } catch (_) {
      nova = null;
    }
    // resposta de um pedido antigo (ou de outra conta) é descartada
    if (geracao != _geracaoCarteira) return;
    carteira = nova;
    notifyListeners();
  }

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
      // a carteira da conta anterior não vale
      carteira = null;
    }
    if (entrou || trocouConta) {
      unawaited(_carregarCarteira());
      unawaited(atualizar());
    }
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
    _estado.aplicarRelatoriosNovos(nova.novos);
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

  /// true quando o relatório foi aberto.
  Future<bool> _abrir(String nome, {required bool escolha}) async {
    final geracao = ++_geracaoAbrir;
    if (escolha) _pedido = nome;
    var abriu = false;
    try {
      final r = await _servicos.abrirRelatorio(nome);
      if (geracao != _geracaoAbrir) return false;
      if (escolha) _escolhido = nome;
      nomeAberto = nome;
      aberto = r;
      erro = null;
      abriu = true;
    } catch (e) {
      if (geracao != _geracaoAbrir || e is PedidoSuperado) return false;
      if (e is EscopoInsuficiente) {
        unawaited(atualizar());
        return false;
      }
      erro = textoErro(e);
    } finally {
      if (geracao == _geracaoAbrir) _pedido = null;
    }
    notifyListeners();
    return abriu;
  }

  /// "Abrir" da faixa de relatório novo: abre o mais recente e, se abriu, zera
  /// o aviso.
  Future<void> abrirNovo() async {
    final novo = _estado.relatoriosNovos.firstOrNull;
    if (novo == null) return;
    if (await _abrir(novo.nome, escolha: true)) {
      await _estado.dispensarRelatoriosNovos();
    }
  }

  /// "Dispensar" da faixa.
  Future<void> dispensarNovo() => _estado.dispensarRelatoriosNovos();

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
