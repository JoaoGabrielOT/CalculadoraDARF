// Serviços de eco para o teste do isolate: cada método devolve um valor que
// carrega os argumentos recebidos, para provar que a chamada atravessou o
// isolate inteira. Roda dentro do isolate (função de nível superior).

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/servicos/parametros.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';

import 'dados_exemplo.dart';

ServicosApp criarServicosEco(
  ParametrosServicos p,
  AbrirUrl abrirUrl,
  void Function(EventoServico) emitir,
) {
  // eventos emitidos durante a montagem, antes de a interface assinar
  if (p.pastaTemporaria == 'cedo') {
    emitir(const EventoAviso('cedo', 'primeiro'));
    emitir(const EventoAviso('cedo', 'segundo'));
  }
  if (p.pastaTemporaria == 'muitos') {
    for (var i = 0; i < 300; i++) {
      emitir(EventoAviso('muitos', '$i'));
    }
  }
  return ServicosEco(abrirUrl, emitir);
}

/// Erro com um campo que não viaja entre isolates.
class ErroNaoEnviavel implements Exception {
  // a porta só existe para tornar o erro não enviável; fechada, não vaza
  ErroNaoEnviavel(this.texto) : porta = ReceivePort()..close();

  final String texto;
  final ReceivePort porta;

  @override
  String toString() => texto;
}

ResultadoVenda _resultado() => ResultadoVenda(
  dt: false,
  compra: 1,
  venda: 2,
  taxas: 0,
  corretagem: 0,
  bruto: 1,
  liquido: 1,
);

Projecao _projecao(double lucro) => Projecao(
  c: _resultado(),
  imposto: 0,
  irrf: 0,
  darfEstimado: 0,
  custos: 0,
  lucroAposImposto: lucro,
);

Meta _meta(String id, String loteId, int qtd, double alvo) => Meta(
  id: id,
  ticker: 'PETR4',
  loteId: loteId,
  qtd: qtd,
  precoAlvo: alvo,
  criadaEm: '2026-10-21T11:00:00-03:00',
);

class ServicosEco implements ServicosApp {
  ServicosEco(this._abrirUrl, this._emitir);

  final AbrirUrl _abrirUrl;
  final void Function(EventoServico) _emitir;

  VisaoMes _visao(String mes, {String? amigo}) =>
      visaoExemplo(Mes(mes: mes), amigo: amigo);

  @override
  Stream<EventoServico> get eventos => const Stream.empty();

  @override
  Future<EstadoInicial> iniciar() async => EstadoInicial(
    mesInicial: '2026-10',
    mesesComDados: const ['2026-10'],
    preferencias: const Preferencias(ordemRadar: 'eco'),
    erroConfig: 'eco',
    temCredencial: true,
  );

  bool _morrerAoEncerrar = false;

  /// Com [_morrerAoEncerrar], um erro assíncrono solto derruba o isolate no
  /// meio do encerramento.
  @override
  Future<void> encerrar() async {
    if (!_morrerAoEncerrar) return;
    Timer.run(() => throw StateError('morreu ao encerrar'));
    await Completer<void>().future;
  }

  @override
  Future<void> salvarPreferencias(Preferencias p) async {
    _emitir(EventoAviso('preferencias', '${p.tema.chave}|${p.ordemRadar}'));
  }

  @override
  Future<List<String>> mesesComDados({String? amigo}) async => ['m:$amigo'];

  @override
  Future<String> mesInicial({String? amigo}) async => 'inicial:$amigo';

  @override
  Future<VisaoMes> carregarMes(String mes, {String? amigo}) async =>
      _visao(mes, amigo: amigo);

  @override
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) async => SugestoesTicker(tickers: [mes, '$soCustodia'], tipos: const {});

  @override
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) async =>
      _visao('$mes/${c.ticker}');

  @override
  Future<VisaoMes> editarCompra(
    String mes,
    String loteId,
    NovaCompra c,
  ) async => _visao('$mes/$loteId/${c.qtd}');

  @override
  Future<VisaoMes> excluirCompra(String mes, String loteId) async =>
      _visao('$mes/$loteId');

  @override
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) async =>
      VendaRegistrada(
        visao: _visao(mes),
        mesGravado: v.loteId,
        aviso: '${v.data}|${v.qtd}|${v.preco}',
      );

  @override
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) async =>
      _visao('$mes/$vendaId/${v.qtd}');

  @override
  Future<VisaoMes> excluirVenda(String mes, String vendaId) async =>
      _visao('$mes/$vendaId');

  @override
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) async => {
    mesAtual,
  };

  @override
  Future<int> reservadoEmMetas(String loteId) async => loteId.length;

  @override
  Future<PreparoFechamento> prepararFechamento(String mes) async =>
      PreparoFechamento()..bloqueio = 'bloqueio $mes';

  @override
  Future<Fechamento> fecharMes(String mes) async =>
      Fechamento(visao: _visao(mes), mensagem: 'fechou $mes');

  @override
  Future<VisaoCaixa> caixa({String? amigo}) async => caixaExemplo(saldo: 123);

  @override
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) async =>
      caixaExemplo(saldo: valor + modo.index);

  @override
  Future<EstadoConta> conta() async =>
      const EstadoConta(email: 'eco@exemplo.com', ultimoErro: 'eco');

  /// Pede à interface para abrir o navegador; a falha dela vira o erro daqui.
  @override
  Future<void> conectar() => _abrirUrl(Uri.parse('https://exemplo.com/login'));

  @override
  Future<void> cancelarLogin() async {}

  @override
  Future<void> sair() async {}

  @override
  Future<void> sincronizarAgora() async {
    _emitir(const EventoAviso('eco', 'sincronizou'));
  }

  @override
  Future<List<Amigo>> amigos() async => [
    Amigo(email: 'a@exemplo.com', desde: '2026-10-28'),
  ];

  @override
  Future<void> adicionarAmigo(String email) async {
    if (email.contains('invalido')) throw ErroValidacao('Amigo inválido.');
    if (email.contains('naoenviavel')) throw ErroNaoEnviavel('texto do erro');
    if (email.contains('morre')) {
      Timer.run(() => throw StateError('boom do isolate'));
      await Completer<void>().future;
    }
  }

  @override
  Future<void> removerAmigo(String email) async {
    if (email.contains('falha')) throw ErroGoogle('O Google recusou.', 403);
    if (email.contains('pendura')) await Completer<void>().future;
    if (email.contains('morreaoencerrar')) _morrerAoEncerrar = true;
  }

  @override
  Future<ResumoAmigo> carregarAmigo(String email) async => ResumoAmigo(
    email: email,
    meses: const ['2026-09'],
    mesInicial: '2026-09',
  );

  @override
  Future<void> esquecerAmigo() async {}

  @override
  Future<VisaoRadar> radar({String? amigo}) async => VisaoRadar(
    itens: radarExemplo(),
    custodia: {'x:$amigo'},
    meus: const {},
    amigo: amigo,
  );

  @override
  Future<ItemRadar> adicionarRadar(String ticker) async =>
      ItemRadar(ticker: ticker, desde: '2026-10-01');

  @override
  Future<int> importarRadar(List<ItemRadar> itens) async => itens.length;

  @override
  Future<void> removerRadar(String ticker) async {}

  @override
  Future<void> reordenarRadar(List<String> tickers) async {}

  @override
  Future<void> limparCacheCotacoes() async {}

  @override
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) async {
    if (ticker == 'REDE') throw ErroConexao('Sem conexão com o Yahoo.');
    return CotacaoErro(ticker, 'eco:$nome');
  }

  @override
  Future<Grafico> grafico(String ticker, String periodo) async => Grafico(
    ticker: ticker,
    periodo: periodo,
    pontos: const [(1, 2.5)],
    referencia: 2,
    desvio: 0,
    intradiario: true,
  );

  @override
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) async => {
    for (final t in tickers) t: t.length.toDouble(),
    'nulo': null,
  };

  @override
  Future<(double, String)> precoVenda(String ticker, String dia) async =>
      (1.5, '$ticker@$dia');

  @override
  Future<VisaoMetas> metas() async => VisaoMetas(
    metas: metasExemplo(),
    descricoes: const {},
    lotes: const [],
    ativas: 7,
  );

  @override
  Future<VisaoSugestoes> sugestoesMetas() async =>
      const VisaoSugestoes(itens: [], rodape: []);

  @override
  Future<PrecoAlvo> calcularPrecoAlvo(
    String loteId,
    int qtd,
    double lucro,
  ) async => PrecoAlvo(
    p: _projecao(lucro),
    preco: qtd.toDouble(),
    precoExato: 0,
    precoMedio: 0,
    brutoNecessario: 0,
    lucroDesejado: lucro,
    qtd: qtd,
    dayTrade: false,
  );

  @override
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) async =>
      _projecao(preco);

  @override
  Future<Meta?> parceiraOco(String loteId, String gatilho) async =>
      gatilho == 'nenhuma' ? null : _meta('oco', loteId, 1, 1);

  @override
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) async => _meta('alvo:$ocoCom:$lucroDesejado', loteId, qtd, precoAlvo);

  @override
  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) async => _meta('stop:$movel:$ocoCom:$precoAtual', loteId, qtd, precoStop);

  @override
  Future<void> cancelarMeta(String metaId) async {}

  @override
  Future<ResultadoVerificacao> verificarMetas() async =>
      const VerificacaoFalhou('eco');

  @override
  Future<VisaoNoticias> noticias() async => _noticias(1);

  @override
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) async =>
      _noticias(forcar ? 2 : 3);

  VisaoNoticias _noticias(int naoLidas) => VisaoNoticias(
    itens: noticiasExemplo(),
    detalhes: const {},
    naoLidas: naoLidas,
    hora: 1,
    lidasAte: 0,
    erros: const {},
    rodando: false,
    radar: const [],
  );

  @override
  Future<void> marcarNoticiasLidas() async {}

  @override
  Future<ImagemBytes?> logo(String ticker) async =>
      ImagemBytes(bytes: Uint8List.fromList([1, 2, 3]), svg: true);

  @override
  Future<Uint8List?> favicon(Noticia item) async =>
      Uint8List.fromList(item.id.codeUnits);

  @override
  Future<Uint8List?> imagemNoticia(String url) async => null;

  @override
  Future<InfoAtualizacao?> verificarAtualizacao() async =>
      const InfoAtualizacao(
        versao: '9.9.9',
        notas: 'eco',
        url: 'https://exemplo.com/a.exe',
        tamanho: 10,
        sha256: 'abc',
      );

  @override
  Future<String> baixarAtualizacao(InfoAtualizacao info) async {
    if (info.versao == 'erro') {
      throw ErroAtualizacao('Resposta inválida do GitHub.');
    }
    if (info.versao == 'longo') {
      final c = _cancelado = Completer<void>();
      _emitir(const EventoProgresso(1, 10)); // o teste cancela depois deste
      await c.future;
      throw ErroAtualizacao('Atualização cancelada.');
    }
    return 'baixou ${info.versao}';
  }

  Completer<void>? _cancelado;

  @override
  Future<void> cancelarDownload() async {
    final c = _cancelado;
    if (c != null && !c.isCompleted) c.complete();
  }
}
