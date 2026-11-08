// Fachada dos serviços no isolate do núcleo: um só `Repositorio`, um só dono.
// Apuração e caixa vêm de `ApuracaoLocal`, conta e amigos de `ContaLocal`,
// mercado, radar e metas de `MercadoLocal`, notícias e imagens de
// `NoticiasLocal`, atualização de `AtualizadorLocal`.

import 'dart:async';
import 'dart:typed_data';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../tema/tema_visual.dart';
import 'api.dart';
import 'eventos.dart';
import 'locais/apuracao_local.dart';
import 'locais/atualizador_local.dart';
import 'locais/config_segura.dart';
import 'locais/conta_local.dart';
import 'locais/mercado_local.dart';
import 'locais/noticias_local.dart';

class ServicosLocais implements ServicosApp {
  ServicosLocais({
    required this._repo,
    required ServicoYahoo yahoo,
    required ContaGoogle conta,
    required AbrirUrl abrirUrl,
    Duration atrasoAgendamento = const Duration(milliseconds: 1500),
    NoticiasLocal Function(void Function(EventoServico))? noticias,
    AtualizadorLocal Function(void Function(EventoServico))? atualizador,
  }) {
    // Quem não usa notícias nem atualização (testes de apuração) não monta.
    _noticiasLocal = noticias?.call(_emitir);
    _atualizadorLocal = atualizador?.call(_emitir);
    _conta = ContaLocal(
      repo: _repo,
      conta: conta,
      abrirUrl: abrirUrl,
      emitir: _emitir,
      atrasoAgendamento: atrasoAgendamento,
    );
    _apuracao = ApuracaoLocal(
      _repo,
      agendarSync: _conta.agendar,
      emitir: _emitir,
      amigoAtual: () => _conta.amigoCarregado,
    );
    _mercado = MercadoLocal(
      repo: _repo,
      yahoo: yahoo,
      agendarSync: _conta.agendar,
      emitir: _emitir,
      amigo: () => _conta.amigoCarregado,
    );
  }

  final Repositorio _repo;
  final StreamController<EventoServico> _eventos =
      StreamController<EventoServico>.broadcast();
  late final ContaLocal _conta;
  late final ApuracaoLocal _apuracao;
  late final MercadoLocal _mercado;
  late final NoticiasLocal? _noticiasLocal;
  late final AtualizadorLocal? _atualizadorLocal;

  NoticiasLocal get _noticias =>
      _noticiasLocal ?? (throw StateError('Notícias não configuradas.'));

  AtualizadorLocal get _atualizador =>
      _atualizadorLocal ?? (throw StateError('Atualizador não configurado.'));

  void _emitir(EventoServico e) {
    if (!_eventos.isClosed) _eventos.add(e);
  }

  /// `tick` da sincronização, chamado pelo timer (Tarefa 7).
  Future<void> tickSync() => _conta.tick();

  /// Guarda os dados do amigo carregado (somente leitura).
  void usarAmigo(String email, DadosPlanilha dados) =>
      _conta.usarAmigo(email, dados);

  void limparAmigo() => _conta.limparAmigo();

  @override
  Stream<EventoServico> get eventos => _eventos.stream;

  // --- ciclo e preferências

  Preferencias _preferenciasDe(Config cfg) {
    final x = cfg.extras;
    final ordem = x['radar_ordem_lista'];
    return Preferencias(
      tema: TemaVisual.daChave(x['tema_visual']),
      notificarNoticias: x['noticias_notificar'] is bool
          ? x['noticias_notificar']! as bool
          : true,
      ordemRadar: ordensRadar.any((o) => o.$1 == ordem)
          ? ordem! as String
          : 'manual',
    );
  }

  @override
  Future<EstadoInicial> iniciar() async {
    Config? cfg;
    String? erroConfig;
    try {
      cfg = lerConfigParaGravar(_repo);
    } on ErroValidacao catch (e) {
      erroConfig = e.mensagem;
    }

    // Com a config ilegível os tipos dos meses ainda são corrigidos, mas
    // `pendente` não é marcado (nada é gravado na config).
    // Corrige o tipo (Ação/BDR) gravado; um mês ilegível fica como está e a
    // Apuração mostra o aviso dele.
    var mudou = false;
    for (final mes in _repo.listarMeses()) {
      try {
        final d = _repo.carregar(mes);
        if (corrigirTiposMes(d)) {
          _repo.salvar(d);
          mudou = true;
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on RangeError {
        continue;
      } on ErroNucleo {
        continue;
      }
    }
    if (mudou && cfg != null) {
      cfg.pendente = true;
      _repo.gravarConfig(cfg);
      _conta.agendar();
    }

    if (erroConfig != null) _emitir(EventoConfigIlegivel(erroConfig));
    return EstadoInicial(
      mesInicial: _apuracao.mesInicialSync(),
      mesesComDados: _repo.listarMeses(),
      preferencias: _preferenciasDe(cfg ?? Config()),
      erroConfig: erroConfig,
      temCredencial: _conta.estado().temCredencial,
    );
  }

  @override
  Future<void> encerrar() async {
    _conta.encerrar();
    if (!_eventos.isClosed) await _eventos.close();
  }

  @override
  Future<void> salvarPreferencias(Preferencias p) async {
    if (!ordensRadar.any((o) => o.$1 == p.ordemRadar)) {
      throw ErroValidacao('Ordem do radar inválida.');
    }
    final cfg = lerConfigParaGravar(_repo);
    cfg.extras['tema_visual'] = p.tema.chave;
    cfg.extras['noticias_notificar'] = p.notificarNoticias;
    cfg.extras['radar_ordem_lista'] = p.ordemRadar;
    _repo.gravarConfig(cfg);
  }

  // --- apuração

  @override
  Future<List<String>> mesesComDados({String? amigo}) =>
      _apuracao.mesesComDados(amigo: amigo);

  @override
  Future<String> mesInicial({String? amigo}) =>
      _apuracao.mesInicial(amigo: amigo);

  @override
  Future<VisaoMes> carregarMes(String mes, {String? amigo}) =>
      _apuracao.carregarMes(mes, amigo: amigo);

  @override
  Future<VisaoPosicoes> posicoes(String mes, {String? amigo}) =>
      _apuracao.posicoes(mes, amigo: amigo);

  @override
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) => _apuracao.sugestoesTicker(mes, soCustodia: soCustodia);

  @override
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) =>
      _apuracao.registrarCompra(mes, c);

  @override
  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c) =>
      _apuracao.editarCompra(mes, loteId, c);

  @override
  Future<VisaoMes> excluirCompra(String mes, String loteId) =>
      _apuracao.excluirCompra(mes, loteId);

  @override
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) =>
      _apuracao.registrarVenda(mes, v);

  @override
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) =>
      _apuracao.editarVenda(mes, vendaId, v);

  @override
  Future<VisaoMes> excluirVenda(String mes, String vendaId) =>
      _apuracao.excluirVenda(mes, vendaId);

  @override
  Future<String> novoGrupoVenda() => _apuracao.novoGrupoVenda();

  @override
  Future<List<Lote>> comprasElegiveis(String mes, String ticker, String data) =>
      _apuracao.comprasElegiveis(mes, ticker, data);

  @override
  Future<PreviaVenda> previaVenda(String mes, NovaVendaQtd v) =>
      _apuracao.previaVenda(mes, v);

  @override
  Future<VendaRegistrada> registrarVendaQtd(String mes, NovaVendaQtd v) =>
      _apuracao.registrarVendaQtd(mes, v);

  @override
  Future<VisaoMes> editarGrupoVenda(String mes, String grupo, NovaVendaQtd v) =>
      _apuracao.editarGrupoVenda(mes, grupo, v);

  @override
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) =>
      _apuracao.mesesSemVendaRetroativa(mesAtual);

  @override
  Future<int> reservadoEmMetas(String loteId) =>
      _apuracao.reservadoEmMetas(loteId);

  @override
  Future<PreparoFechamento> prepararFechamento(String mes) =>
      _mercado.prepararFechamento(mes);

  @override
  Future<Fechamento> fecharMes(String mes) => _apuracao.fecharMes(mes);

  // --- caixa

  @override
  Future<VisaoCaixa> caixa({String? amigo}) => _apuracao.caixa(amigo: amigo);

  @override
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) =>
      _apuracao.alterarSaldo(modo, valor);

  // --- conta, sincronização e amigos (Tarefa 4)

  @override
  Future<EstadoConta> conta() async => _conta.estado();

  @override
  Future<void> conectar() => _conta.conectar();

  @override
  Future<void> cancelarLogin() => _conta.cancelarLogin();

  @override
  Future<void> sair() => _conta.sair();

  @override
  Future<void> sincronizarAgora() => _conta.sincronizarAgora();

  @override
  Future<List<Amigo>> amigos() => _conta.amigos();

  @override
  Future<void> adicionarAmigo(String email) => _conta.adicionarAmigo(email);

  @override
  Future<void> removerAmigo(String email) => _conta.removerAmigo(email);

  @override
  Future<ResumoAmigo> carregarAmigo(String email) =>
      _conta.carregarAmigo(email);

  @override
  Future<void> esquecerAmigo() => _conta.esquecerAmigo();

  // --- mercado, radar e metas (Tarefa 5)

  /// Verificação de metas do timer (Tarefa 7).
  Future<void> verificacaoAutomatica() => _mercado.verificacaoAutomatica();

  @override
  Future<VisaoRadar> radar({String? amigo}) => _mercado.radar(amigo: amigo);

  @override
  Future<ItemRadar> adicionarRadar(String ticker) =>
      _mercado.adicionarRadar(ticker);

  @override
  Future<int> importarRadar(List<ItemRadar> itens) =>
      _mercado.importarRadar(itens);

  @override
  Future<void> removerRadar(String ticker) => _mercado.removerRadar(ticker);

  @override
  Future<void> reordenarRadar(List<String> tickers) =>
      _mercado.reordenarRadar(tickers);

  @override
  Future<void> limparCacheCotacoes() => _mercado.limparCacheCotacoes();

  @override
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) =>
      _mercado.cotacao(ticker, nome: nome);

  @override
  Future<Grafico> grafico(String ticker, String periodo) =>
      _mercado.grafico(ticker, periodo);

  @override
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) =>
      _mercado.precosCarteira(tickers);

  @override
  Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers) =>
      _mercado.cotacoesAtuais(tickers);

  @override
  Future<(double, String)> precoVenda(String ticker, String dia) =>
      _mercado.precoVenda(ticker, dia);

  @override
  Future<VisaoMetas> metas() => _mercado.metas();

  @override
  Future<VisaoSugestoes> sugestoesMetas({bool incluirRadar = false}) =>
      _mercado.sugestoesMetas(incluirRadar: incluirRadar);

  @override
  Future<PrecoAlvo> calcularPrecoAlvo(String loteId, int qtd, double lucro) =>
      _mercado.calcularPrecoAlvo(loteId, qtd, lucro);

  @override
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) =>
      _mercado.projetarPreco(loteId, qtd, preco);

  @override
  Future<Meta?> parceiraOco(String loteId, String gatilho) =>
      _mercado.parceiraOco(loteId, gatilho);

  @override
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) => _mercado.criarMetaAlvo(
    loteId,
    qtd,
    precoAlvo,
    lucroDesejado: lucroDesejado,
    ocoCom: ocoCom,
  );

  @override
  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) => _mercado.criarStop(
    loteId,
    qtd,
    precoStop,
    movel: movel,
    ocoCom: ocoCom,
    precoAtual: precoAtual,
    sugestao: sugestao,
  );

  @override
  Future<void> cancelarMeta(String metaId) => _mercado.cancelarMeta(metaId);

  @override
  Future<ResultadoVerificacao> verificarMetas() => _mercado.verificarMetas();

  // --- notícias, imagens e atualizador (Tarefa 6)

  /// Passo do timer de notícias (Tarefa 7).
  Future<void> tickNoticias() => _noticias.tick();

  @override
  Future<VisaoNoticias> noticias() => _noticias.noticias();

  @override
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) =>
      _noticias.atualizarNoticias(forcar: forcar);

  @override
  Future<void> marcarNoticiasLidas() => _noticias.marcarNoticiasLidas();

  @override
  Future<ImagemBytes?> logo(String ticker) => _noticias.logo(ticker);

  @override
  Future<Uint8List?> favicon(Noticia item) => _noticias.favicon(item);

  @override
  Future<Uint8List?> imagemNoticia(String url) => _noticias.imagemNoticia(url);

  @override
  Future<InfoAtualizacao?> verificarAtualizacao() =>
      _atualizador.verificarAtualizacao();

  @override
  Future<String> baixarAtualizacao(InfoAtualizacao info) =>
      _atualizador.baixarAtualizacao(info);

  @override
  Future<void> cancelarDownload() => _atualizador.cancelarDownload();
}
