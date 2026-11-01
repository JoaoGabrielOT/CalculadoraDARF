// Fachada dos serviços no isolate do núcleo: um só `Repositorio`, um só dono.
// Apuração e caixa vêm de `ApuracaoLocal`; conta, mercado, notícias e
// atualizador entram nas Tarefas 4 a 6.

import 'dart:async';
import 'dart:typed_data';

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../tema/tema_visual.dart';
import 'api.dart';
import 'eventos.dart';
import 'locais/apuracao_local.dart';
import 'locais/config_segura.dart';

class ServicosLocais implements ServicosApp {
  ServicosLocais({
    required this._repo,
    required this._agendarSync,
    bool Function()? temCredencial,
  }) : _temCredencial = temCredencial ?? (() => false);

  final Repositorio _repo;
  final bool Function() _temCredencial;
  final void Function() _agendarSync;
  final StreamController<EventoServico> _eventos =
      StreamController<EventoServico>.broadcast();

  /// Dados do amigo carregado (preenchido pela Tarefa 4).
  AmigoCarregado? _amigo;

  late final ApuracaoLocal _apuracao = ApuracaoLocal(
    _repo,
    agendarSync: _agendarSync,
    emitir: _emitir,
    amigoAtual: () => _amigo,
  );

  void _emitir(EventoServico e) {
    if (!_eventos.isClosed) _eventos.add(e);
  }

  /// Guarda os dados do amigo carregado (somente leitura).
  void usarAmigo(String email, DadosPlanilha dados) {
    _amigo = (email: email, dados: dados);
  }

  void limparAmigo() => _amigo = null;

  Never _faltaImplementar(String tarefa) =>
      throw UnimplementedError('Chega na $tarefa.');

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
      _agendarSync();
    }

    if (erroConfig != null) _emitir(EventoConfigIlegivel(erroConfig));
    return EstadoInicial(
      mesInicial: _apuracao.mesInicialSync(),
      mesesComDados: _repo.listarMeses(),
      preferencias: _preferenciasDe(cfg ?? Config()),
      erroConfig: erroConfig,
      temCredencial: _temCredencial(),
    );
  }

  @override
  Future<void> encerrar() async {
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
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) =>
      _apuracao.mesesSemVendaRetroativa(mesAtual);

  @override
  Future<int> reservadoEmMetas(String loteId) =>
      _apuracao.reservadoEmMetas(loteId);

  @override
  Future<PreparoFechamento> prepararFechamento(String mes) async =>
      _faltaImplementar('Tarefa 5');

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
  Future<EstadoConta> conta() async => _faltaImplementar('Tarefa 4');

  @override
  Future<void> conectar() async => _faltaImplementar('Tarefa 4');

  @override
  Future<void> cancelarLogin() async => _faltaImplementar('Tarefa 4');

  @override
  Future<void> sair() async => _faltaImplementar('Tarefa 4');

  @override
  Future<void> sincronizarAgora() async => _faltaImplementar('Tarefa 4');

  @override
  Future<List<Amigo>> amigos() async => _faltaImplementar('Tarefa 4');

  @override
  Future<void> adicionarAmigo(String email) async =>
      _faltaImplementar('Tarefa 4');

  @override
  Future<void> removerAmigo(String email) async =>
      _faltaImplementar('Tarefa 4');

  @override
  Future<ResumoAmigo> carregarAmigo(String email) async =>
      _faltaImplementar('Tarefa 4');

  @override
  Future<void> esquecerAmigo() async => _faltaImplementar('Tarefa 4');

  // --- mercado, radar e metas (Tarefa 5)

  @override
  Future<VisaoRadar> radar({String? amigo}) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<ItemRadar> adicionarRadar(String ticker) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<int> importarRadar(List<ItemRadar> itens) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<void> removerRadar(String ticker) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<void> reordenarRadar(List<String> tickers) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<void> limparCacheCotacoes() async => _faltaImplementar('Tarefa 5');

  @override
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<Grafico> grafico(String ticker, String periodo) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<(double, String)> precoVenda(String ticker, String dia) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<VisaoMetas> metas() async => _faltaImplementar('Tarefa 5');

  @override
  Future<VisaoSugestoes> sugestoesMetas() async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<PrecoAlvo> calcularPrecoAlvo(
    String loteId,
    int qtd,
    double lucro,
  ) async => _faltaImplementar('Tarefa 5');

  @override
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<Meta?> parceiraOco(String loteId, String gatilho) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) async => _faltaImplementar('Tarefa 5');

  @override
  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) async => _faltaImplementar('Tarefa 5');

  @override
  Future<void> cancelarMeta(String metaId) async =>
      _faltaImplementar('Tarefa 5');

  @override
  Future<ResultadoVerificacao> verificarMetas() async =>
      _faltaImplementar('Tarefa 5');

  // --- notícias, imagens e atualizador (Tarefa 6)

  @override
  Future<VisaoNoticias> noticias() async => _faltaImplementar('Tarefa 6');

  @override
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<void> marcarNoticiasLidas() async => _faltaImplementar('Tarefa 6');

  @override
  Future<ImagemBytes?> logo(String ticker) async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<Uint8List?> favicon(Noticia item) async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<Uint8List?> imagemNoticia(String url) async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<InfoAtualizacao?> verificarAtualizacao() async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<String> baixarAtualizacao(InfoAtualizacao info) async =>
      _faltaImplementar('Tarefa 6');

  @override
  Future<void> cancelarDownload() async => _faltaImplementar('Tarefa 6');
}
