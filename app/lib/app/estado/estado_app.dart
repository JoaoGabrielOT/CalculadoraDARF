// Estado global do app: preferências, conta, visão de amigo, mês, aba e
// avisos. Fala só com `ServicosApp` e `Plataforma`; sem IO nem plugins.

import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../plataforma/plataforma.dart';
import '../regras/textos.dart';
import '../servicos/api.dart';
import '../servicos/eventos.dart';
import '../tema/tema_visual.dart';

enum Aba { apuracao, caixa, radar, noticias, conta }

class EstadoApp extends ChangeNotifier {
  EstadoApp(this._servicos, this._plataforma) {
    // Assina logo: o proxy só guarda os 256 últimos eventos até a primeira
    // assinatura.
    _assinatura = _servicos.eventos.listen(
      _aoEvento,
      onError: (Object e) => avisar('Erro inesperado', textoErro(e)),
      onDone: _aoFecharEventos,
    );
  }

  final ServicosApp _servicos;
  final Plataforma _plataforma;
  late final StreamSubscription<EventoServico> _assinatura;

  Preferencias preferencias = const Preferencias();
  EstadoConta conta = const EstadoConta();

  /// E-mail do amigo cujos dados estão na tela; null = meus dados.
  String? amigo;
  bool carregandoAmigo = false;
  String mes = ambiente.hoje().substring(0, 7);
  int naoLidas = 0;

  /// Preenchido quando o `config.json` está ilegível.
  String? erroConfig;
  String textoSaldo = 'Saldo: —';
  Aba aba = Aba.apuracao;

  /// Sobe a cada `EventoDadosMudaram`: as telas recarregam quando muda.
  int versaoDados = 0;
  InfoAtualizacao? atualizacao;

  /// Metas ativas, para o "· N ativas" do cabeçalho.
  int metasAtivas = 0;

  /// Fila consumida pela casca.
  final List<EventoAviso> avisos = [];

  /// Verdadeiro até o estado inicial chegar: a casca mostra o carregamento
  /// em vez de piscar com as preferências padrão.
  bool carregando = true;

  /// Motivo da falha de `servicos.iniciar()`; a casca oferece "Tentar de novo".
  String? falhaInicial;

  /// O isolate de serviços morreu sem o app pedir (faixa fixa na casca).
  bool servicosEncerrados = false;

  bool _iniciado = false;
  bool _iniciando = false;
  bool _inicialAplicado = false;
  bool _conferindo = false;
  bool _reconferir = false;

  /// E-mail do amigo cuja carga está em voo.
  String? _pedido;
  bool _descartado = false;
  bool _avisouNotificacao = false;
  int _geracaoVisao = 0;

  @override
  void notifyListeners() {
    if (!_descartado) super.notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    unawaited(_assinatura.cancel());
    super.dispose();
  }

  /// Chamado uma única vez na vida do app: uma segunda chamada reenviaria o
  /// link da partida a frio (`iniciarNotificacoes`).
  ///
  /// Se `servicos.iniciar()` falha, vira [falhaInicial] e uma nova chamada
  /// tenta de novo; o resto só roda depois que ele dá certo.
  Future<void> iniciar() async {
    if (_iniciado || _iniciando) return;
    _iniciando = true;
    if (!_inicialAplicado) {
      if (falhaInicial != null) {
        falhaInicial = null;
        carregando = true;
        notifyListeners();
      }
      try {
        aplicarInicial(await _servicos.iniciar());
      } catch (e) {
        falhaInicial = textoFalha(e);
        carregando = false;
        _iniciando = false;
        notifyListeners();
        return;
      }
    }
    _iniciado = true;
    _iniciando = false;
    await Future.wait([
      _atualizarConta(),
      atualizarSaldo(),
      _atualizarNaoLidas(),
      _atualizarMetas(),
      _iniciarNotificacoes(),
    ]);
    unawaited(_verificarAtualizacao());
  }

  /// Aplica o resultado de `servicos.iniciar()`. `iniciarApp` chama antes do
  /// `runApp`, para o primeiro quadro já sair com o tema gravado; nesse caso
  /// [iniciar] não chama os serviços de novo.
  void aplicarInicial(EstadoInicial inicial) {
    preferencias = inicial.preferencias;
    mes = inicial.mesInicial;
    erroConfig = inicial.erroConfig;
    falhaInicial = null;
    carregando = false;
    _inicialAplicado = true;
    notifyListeners();
  }

  /// O fim do stream sem o app ter descartado o estado é a morte do isolate
  /// (o app não tem encerramento normal que feche o stream antes).
  void _aoFecharEventos() {
    if (_descartado) return;
    servicosEncerrados = true;
    notifyListeners();
  }

  void irPara(Aba nova) {
    if (nova == aba) return;
    aba = nova;
    notifyListeners();
  }

  void avisar(String titulo, String texto) {
    avisos.add(EventoAviso(titulo, texto));
    notifyListeners();
  }

  /// Próximo aviso da fila (a casca o mostra), ou null.
  EventoAviso? proximoAviso() => avisos.isEmpty ? null : avisos.removeAt(0);

  // --- preferências

  Preferencias _com({
    TemaVisual? tema,
    bool? notificarNoticias,
    String? ordemRadar,
  }) => Preferencias(
    tema: tema ?? preferencias.tema,
    notificarNoticias: notificarNoticias ?? preferencias.notificarNoticias,
    ordemRadar: ordemRadar ?? preferencias.ordemRadar,
  );

  /// Muda na hora; se a gravação falhar, mostra o erro e o tema da sessão
  /// continua.
  Future<void> trocarTema(TemaVisual t) async {
    preferencias = _com(tema: t);
    notifyListeners();
    await _gravarPreferencias();
  }

  Future<void> definirNotificar(bool v) async {
    preferencias = _com(notificarNoticias: v);
    notifyListeners();
    if (await _gravarPreferencias() && v && !_plataforma.windows) {
      await _pedirPermissao();
    }
  }

  Future<void> definirOrdemRadar(String chave) async {
    preferencias = _com(ordemRadar: chave);
    notifyListeners();
    await _gravarPreferencias();
  }

  /// Devolve se gravou.
  Future<bool> _gravarPreferencias() async {
    try {
      await _servicos.salvarPreferencias(preferencias);
      return true;
    } catch (e) {
      avisar('Não foi possível salvar', textoErro(e));
      return false;
    }
  }

  // --- visão (meus dados ou amigo) e mês

  /// `null` volta para "Meus dados". Vale o último pedido; o erro de um
  /// pedido superado ("... foi cancelado.") não aparece (py:3001-3009).
  Future<void> trocarVisao(String? email) async {
    if (email == null && amigo == null && !carregandoAmigo) return;
    final geracao = ++_geracaoVisao;
    if (email == null) {
      carregandoAmigo = false;
      try {
        _pedido = null;
        await _servicos.esquecerAmigo();
        final inicial = await _servicos.mesInicial();
        if (geracao != _geracaoVisao) return;
        amigo = null;
        mes = inicial;
      } catch (e) {
        if (geracao != _geracaoVisao) return;
        avisar('Não foi possível carregar', textoErro(e));
      }
      notifyListeners();
      return;
    }
    carregandoAmigo = true;
    _pedido = email;
    notifyListeners();
    try {
      final resumo = await _servicos.carregarAmigo(email);
      if (geracao != _geracaoVisao) return;
      amigo = email;
      mes = resumo.mesInicial;
    } catch (e) {
      if (geracao != _geracaoVisao) return;
      if (!_superado(e)) avisar('Não foi possível carregar', textoErro(e));
    }
    _pedido = null;
    carregandoAmigo = false;
    notifyListeners();
  }

  bool _superado(Object e) => e is PedidoSuperado;

  /// O serviço já limpou o amigo quando o usuário sai da conta ou o remove:
  /// aqui a visão acompanha, invalidando qualquer pedido em voo.
  /// Conferências simultâneas viram uma só mais uma repetição.
  Future<void> _conferirVisao() async {
    if (_conferindo) {
      _reconferir = true;
      return;
    }
    _conferindo = true;
    try {
      do {
        _reconferir = false;
        await _conferirUmaVez();
      } while (_reconferir);
    } finally {
      _conferindo = false;
    }
  }

  Future<void> _conferirUmaVez() async {
    final alvo = amigo ?? _pedido;
    if (alvo == null) return;
    final geracao = _geracaoVisao;
    try {
      var sumiu = conta.email == null;
      if (!sumiu) {
        sumiu = !(await _servicos.amigos()).any((a) => a.email == alvo);
      }
      if (geracao != _geracaoVisao) return;
      if (sumiu) await _voltarAosMeus();
    } catch (_) {
      // sem como conferir: o próximo evento tenta de novo
    }
  }

  Future<void> _voltarAosMeus() async {
    final geracao = ++_geracaoVisao;
    amigo = null;
    _pedido = null;
    carregandoAmigo = false;
    versaoDados++;
    notifyListeners();
    try {
      final inicial = await _servicos.mesInicial();
      if (geracao != _geracaoVisao) return;
      mes = inicial;
      notifyListeners();
    } catch (_) {
      // o mês anterior fica; o seletor do Apuração corrige
    }
  }

  void trocarMes(String novo) {
    mes = novo;
    notifyListeners();
  }

  /// Volta para "Meus dados" e, se o mês exibido estiver fechado, vai para o
  /// mês inicial; devolve a visão aberta (`preparar_operacao`,
  /// calculadora_darf.py:2646-2653).
  Future<VisaoMes> prepararOperacao() async {
    if (amigo != null || carregandoAmigo) await trocarVisao(null);
    var visao = await _servicos.carregarMes(mes);
    if (visao.dados.fechado) {
      final inicial = await _servicos.mesInicial();
      if (inicial != mes) {
        mes = inicial;
        notifyListeners();
        visao = await _servicos.carregarMes(inicial);
      }
    }
    return visao;
  }

  Future<void> atualizarSaldo() async {
    try {
      final r = (await _servicos.caixa()).resumo;
      textoSaldo = r.definido ? 'Saldo: ${brl(r.disponivel)}' : 'Definir saldo';
      notifyListeners();
    } catch (_) {
      // o texto anterior fica; a tela do Caixa mostra o erro
    }
  }

  // --- ciclo de vida

  /// Ao voltar ao primeiro plano, verifica as metas (android/main.py:644-646).
  void aoMudarCiclo(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) unawaited(_verificarMetas());
  }

  Future<void> _verificarMetas() async {
    try {
      await _servicos.verificarMetas();
    } catch (_) {
      // verificação de fundo: o próximo passo do timer tenta de novo
    }
  }

  // --- eventos dos serviços

  void _aoEvento(EventoServico e) {
    switch (e) {
      case EventoConta():
        conta = e.conta;
        notifyListeners();
        unawaited(_conferirVisao());
      case EventoDadosMudaram():
        versaoDados++;
        notifyListeners();
        unawaited(_conferirVisao());
        unawaited(atualizarSaldo());
        unawaited(_atualizarMetas());
      case EventoAviso():
        avisar(e.titulo, semPrefixoException(e.texto));
      case EventoConfigIlegivel():
        erroConfig = e.mensagem;
        notifyListeners();
      case EventoNoticias():
        naoLidas = e.visao.naoLidas;
        notifyListeners();
        unawaited(_notificarNoticias(e.notificar));
      case EventoMetas():
        unawaited(_atualizarMetas());
      case EventoProgresso():
        break;
    }
  }

  Future<void> _atualizarConta() async {
    try {
      conta = await _servicos.conta();
      notifyListeners();
    } catch (_) {
      // os eventos de conta corrigem o estado
    }
  }

  Future<void> _atualizarNaoLidas() async {
    try {
      naoLidas = (await _servicos.noticias()).naoLidas;
      notifyListeners();
    } catch (_) {
      // o selo aparece no próximo evento de notícias
    }
  }

  Future<void> _atualizarMetas() async {
    try {
      metasAtivas = (await _servicos.metas()).ativas;
      notifyListeners();
    } catch (_) {
      // só o "· N ativas" do cabeçalho
    }
  }

  Future<void> _verificarAtualizacao() async {
    try {
      atualizacao = await _servicos.verificarAtualizacao();
      notifyListeners();
    } catch (_) {
      // sem rede ou sem versão nova: silencioso (py:2663)
    }
  }

  // --- notificações (plugins: toda chamada captura a exceção)

  Future<void> _iniciarNotificacoes() async {
    try {
      await _plataforma.iniciarNotificacoes(_aoTocar);
    } catch (e) {
      _avisarNotificacao(e);
    }
    if (preferencias.notificarNoticias && !_plataforma.windows) {
      await _pedirPermissao();
    }
  }

  Future<void> _pedirPermissao() async {
    try {
      await _plataforma.pedirPermissaoNotificacoes();
    } catch (e) {
      _avisarNotificacao(e);
    }
  }

  /// Toque numa notificação: o link da notícia, ou a aba Notícias no resumo.
  void _aoTocar(String link) {
    final uri = link.isEmpty ? null : Uri.tryParse(link);
    if (uri == null) {
      irPara(Aba.noticias);
      return;
    }
    unawaited(_abrirLink(uri));
  }

  Future<void> _abrirLink(Uri uri) async {
    try {
      if (await _plataforma.abrirUrl(uri)) return;
      avisar('Não foi possível abrir', 'Não foi possível abrir o navegador.');
    } catch (e) {
      avisar('Não foi possível abrir', textoErro(e));
    }
  }

  Future<void> _notificarNoticias(List<(String, String, String)> novas) async {
    if (!preferencias.notificarNoticias) return;
    for (final (titulo, corpo, link) in novas) {
      try {
        final id = (link.isEmpty ? titulo : link).hashCode.abs() % 2000000000;
        await _plataforma.notificar(id, titulo, corpo, link);
      } catch (e) {
        _avisarNotificacao(e);
        return;
      }
    }
  }

  /// Uma falha de notificação por sessão, para não repetir o aviso a cada
  /// rodada de notícias.
  void _avisarNotificacao(Object e) {
    if (_avisouNotificacao) return;
    _avisouNotificacao = true;
    avisar('Notificações indisponíveis', textoErro(e));
  }
}
