// Proxy dos serviços para a interface: os serviços reais rodam num isolate
// dedicado (o núcleo, o `Repositorio`, a rede e as imagens ficam fora da
// thread da interface). Sem package:flutter.
//
// Protocolo (listas, só valores enviáveis):
//   interface -> isolate: ['chamar', id, função], ['url', id, abriu]
//   isolate -> interface: ['pronto', porta], ['falha', erro, pilha],
//                         ['res', id, valor], ['err', id, erro, pilha],
//                         ['ev', evento], ['url', id, uri]
// A interface relança o mesmo objeto de erro, com a pilha do isolate.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../integracoes/integracoes.dart';
import '../../nucleo/nucleo.dart';
import '../plataforma/backup.dart';
import 'api.dart';
import 'eventos.dart';
import 'locais/atualizador_local.dart';
import 'locais/noticias_local.dart';
import 'parametros.dart';
import 'servicos_locais.dart';

/// Texto do StateError de um pedido a serviços que já morreram.
const msgServicosEncerrados = 'Serviços encerrados.';
const _msgEncerrado = msgServicosEncerrados;

const _msgNavegador = 'Não foi possível abrir o navegador.';

// calculadora_darf.py:1266-1268 e android/main.py:2395.
Duration intervaloSyncPadrao({required bool windows}) =>
    Duration(seconds: windows ? 60 : 30);
const primeiraMetasPadrao = Duration(milliseconds: 2500);
const intervaloMetasPadrao = Duration(seconds: 60);
const primeiraNoticiasPadrao = Duration(seconds: 8);
const intervaloNoticiasPadrao = Duration(seconds: 60);

http.Client criarClienteReal() => http.Client();

/// Os timers do app: sincronização (primeiro tick na hora), metas e notícias.
/// Nenhum erro de um passo derruba o timer: a próxima passada tenta de novo.
class TimersServicos {
  TimersServicos({
    required this.sync,
    required this.metas,
    required this.noticias,
    required this.intervaloSync,
    this.primeiraMetas = primeiraMetasPadrao,
    this.intervaloMetas = intervaloMetasPadrao,
    this.primeiraNoticias = primeiraNoticiasPadrao,
    this.intervaloNoticias = intervaloNoticiasPadrao,
  });

  final Future<void> Function() sync;
  final Future<void> Function() metas;
  final Future<void> Function() noticias;
  final Duration intervaloSync;
  final Duration primeiraMetas;
  final Duration intervaloMetas;
  final Duration primeiraNoticias;
  final Duration intervaloNoticias;

  final List<Timer> _timers = [];
  bool _parado = false;

  Future<void> _seguro(Future<void> Function() passo) async {
    try {
      await passo();
    } catch (_) {
      // config ilegível, disco ou rede: o aviso vem pelos eventos e pelas
      // telas; o timer continua
    }
  }

  void _agendar(
    Duration primeira,
    Duration intervalo,
    Future<void> Function() passo,
  ) {
    _timers.add(
      Timer(primeira, () {
        if (_parado) return;
        unawaited(_seguro(passo));
        _timers.add(
          Timer.periodic(intervalo, (_) => unawaited(_seguro(passo))),
        );
      }),
    );
  }

  void iniciar() {
    if (_parado) return;
    unawaited(_seguro(sync));
    _timers.add(Timer.periodic(intervaloSync, (_) => unawaited(_seguro(sync))));
    _agendar(primeiraMetas, intervaloMetas, metas);
    _agendar(primeiraNoticias, intervaloNoticias, noticias);
  }

  void cancelar() {
    _parado = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }
}

/// Fachada com os timers e o cliente HTTP do isolate.
class _ServicosReais extends ServicosLocais {
  _ServicosReais({
    required super.repo,
    required super.yahoo,
    required super.conta,
    required super.abrirUrl,
    required super.noticias,
    required super.atualizador,
    required super.fazerBackup,
    required this.cliente,
  });

  final http.Client cliente;
  TimersServicos? timers;
  bool _timersIniciados = false;

  /// Os timers (sincronização no primeiro tick) só começam depois da
  /// partida: o backup da migração vem antes de qualquer sincronização.
  @override
  Future<EstadoInicial> iniciar() async {
    try {
      return await super.iniciar();
    } finally {
      if (!_timersIniciados) {
        _timersIniciados = true;
        timers?.iniciar();
      }
    }
  }

  @override
  Future<void> encerrar() async {
    timers?.cancelar();
    try {
      await super.encerrar();
    } finally {
      cliente.close();
    }
  }
}

/// Monta os serviços reais dentro do isolate.
ServicosApp criarServicosLocais(
  ParametrosServicos p,
  AbrirUrl abrirUrl,
  void Function(EventoServico) emitir,
) {
  final disco = ArmazenamentoArquivos(p.pastaDados);
  final cache = CacheBinarioArquivos(p.pastaDados);
  final c = p.criarCliente();
  final http30 = ClienteHttp(c, tempoLimite: const Duration(seconds: 30));
  final sessao = SessaoGoogle(http: http30, armazenamento: disco);
  final google = Google(
    sessao: sessao,
    planilha: PlanilhaGoogle(sessao),
    httpLogin: http30,
    cliente: p.clienteOAuth,
  );
  final repo = Repositorio(disco);
  final s = _ServicosReais(
    repo: repo,
    yahoo: ServicoYahoo(ServicoYahoo.clientePadrao(c)),
    conta: google,
    abrirUrl: abrirUrl,
    noticias: (emitirLocal) => NoticiasLocal(
      repo: repo,
      servico: ServicoNoticias(cliente: c, armazenamento: disco),
      logos: Logos(http: Logos.clientePadrao(c), cache: cache),
      cache: cache,
      navegador: Logos.clienteNavegador(c),
      emitir: emitirLocal,
    ),
    atualizador: (emitirLocal) => AtualizadorLocal(
      http: ClienteHttp(c),
      pastaTemporaria: p.pastaTemporaria,
      windows: p.windows,
      emitir: emitirLocal,
    ),
    fazerBackup: () => fazerBackup(p.pastaDados, DateTime.now()),
    cliente: c,
  );
  s.eventos.listen(emitir);
  if (p.timers) {
    s.timers = TimersServicos(
      sync: s.tickSync,
      metas: s.verificacaoAutomatica,
      noticias: s.tickNoticias,
      intervaloSync: intervaloSyncPadrao(windows: p.windows),
    );
  }
  return s;
}

// --- isolate

/// Substituto enviável de um erro que não atravessa o isolate: guarda só o
/// texto (a pilha segue como texto no protocolo).
class ErroRemoto implements Exception {
  const ErroRemoto(this.mensagem);

  final String mensagem;

  @override
  String toString() => mensagem;
}

String _textoDe(Object? e) {
  try {
    return e.toString();
  } catch (_) {
    return e.runtimeType.toString();
  }
}

void _enviarSeguro(SendPort porta, List<Object?> msg) {
  try {
    porta.send(msg);
    return;
  } catch (_) {
    // valor não enviável: quem espera uma resposta recebe um erro no lugar
  }
  final List<Object?>? troca = switch (msg[0]) {
    'res' => [
      'err',
      msg[1],
      ErroRemoto('Resposta não enviável: ${msg[2].runtimeType}'),
      StackTrace.current.toString(),
    ],
    'err' => ['err', msg[1], ErroRemoto(_textoDe(msg[2])), msg[3]],
    'falha' => ['falha', ErroRemoto(_textoDe(msg[1])), msg[2]],
    _ => null, // evento ou url: nada espera por eles
  };
  if (troca == null) return;
  try {
    porta.send(troca);
  } catch (_) {
    // texto e ids são sempre enviáveis; sem porta, nada a fazer
  }
}

/// Erro assíncrono solto dentro da zona não derruba os serviços: vira um
/// aviso para a interface e o isolate segue atendendo os pedidos. Só a morte
/// real do isolate (`onExit`, inclusive kill externo) encerra o proxy.
void _principal((ParametrosServicos, SendPort) args) {
  runZonedGuarded(
    () => _executar(args),
    (e, pilha) => _enviarSeguro(args.$2, [
      'ev',
      EventoAviso('Erro inesperado', _textoDe(e)),
    ]),
  );
}

Future<void> _executar((ParametrosServicos, SendPort) args) async {
  final (p, interface) = args;
  final porta = ReceivePort();
  final urls = <int, Completer<bool>>{};
  var proximaUrl = 0;

  Future<void> abrirUrl(Uri url) async {
    final id = proximaUrl++;
    final resposta = urls[id] = Completer<bool>();
    _enviarSeguro(interface, ['url', id, url]);
    if (!await resposta.future) throw ErroGoogle(_msgNavegador);
  }

  final ServicosApp servicos;
  try {
    servicos = p.criarServicos(
      p,
      abrirUrl,
      (e) => _enviarSeguro(interface, ['ev', e]),
    );
  } catch (e, pilha) {
    porta.close();
    _enviarSeguro(interface, ['falha', e, pilha.toString()]);
    return;
  }

  porta.listen((msg) {
    final m = msg as List<Object?>;
    switch (m[0]) {
      case 'url':
        urls.remove(m[1])?.complete(m[2] as bool);
      case 'chamar':
        final id = m[1] as int;
        final funcao = m[2] as Object? Function(ServicosApp);
        Future<Object?>.sync(() => funcao(servicos)).then(
          (v) => _enviarSeguro(interface, ['res', id, v]),
          onError: (Object e, StackTrace pilha) =>
              _enviarSeguro(interface, ['err', id, e, pilha.toString()]),
        );
    }
  });
  interface.send(['pronto', porta.sendPort]);
}

// --- interface

class ServicosIsolate implements ServicosApp {
  ServicosIsolate._(
    this._isolate,
    this._enviar,
    this._recebe,
    this._saida,
    this._abrirUrl,
  ) {
    _eventos = StreamController<EventoServico>.broadcast(
      onListen: () => scheduleMicrotask(_descarregar),
    );
  }

  /// Sobe o isolate; uma exceção em `criarServicos` volta como erro daqui.
  static Future<ServicosIsolate> criar(
    ParametrosServicos p, {
    required Future<bool> Function(Uri) abrirUrl,
  }) async {
    final recebe = ReceivePort();
    final saida = ReceivePort();
    final pronto = Completer<SendPort>();
    ServicosIsolate? proxy;
    // mensagens que chegam antes do proxy existir (eventos da montagem)
    final antes = <List<Object?>>[];
    recebe.listen((msg) {
      final m = msg as List<Object?>;
      switch (m[0]) {
        case 'pronto':
          pronto.complete(m[1] as SendPort);
        case 'falha':
          if (!pronto.isCompleted) {
            pronto.completeError(m[1]!, StackTrace.fromString(m[2] as String));
          }
        default:
          if (proxy == null) {
            antes.add(m);
          } else {
            proxy._tratar(m);
          }
      }
    });
    final isolate = await Isolate.spawn<(ParametrosServicos, SendPort)>(
      _principal,
      (p, recebe.sendPort),
      onExit: saida.sendPort,
    );
    saida.listen((_) {
      if (!pronto.isCompleted) {
        pronto.completeError(StateError(_msgEncerrado));
      }
      proxy?._fechar();
    });
    try {
      final enviar = await pronto.future;
      final novo = proxy = ServicosIsolate._(
        isolate,
        enviar,
        recebe,
        saida,
        abrirUrl,
      );
      antes.forEach(novo._tratar);
      return novo;
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      recebe.close();
      saida.close();
      rethrow;
    }
  }

  final Isolate _isolate;
  final SendPort _enviar;
  final ReceivePort _recebe;
  final ReceivePort _saida;
  final Future<bool> Function(Uri) _abrirUrl;
  final Map<int, Completer<Object?>> _pendentes = {};

  /// Broadcast descartaria o que chega sem ouvinte: até a primeira assinatura
  /// os eventos esperam em [_buffer] e saem na ordem. O buffer guarda no
  /// máximo [_limiteBuffer] eventos (os mais antigos são descartados) e só
  /// vale até a primeira assinatura: depois dela os eventos vão direto ao
  /// stream e quem assina mais tarde não recebe o passado.
  late final StreamController<EventoServico> _eventos;
  static const _limiteBuffer = 256;
  final List<EventoServico> _buffer = [];
  bool _ouvido = false;
  int _proximo = 0;
  bool _aberto = true;
  Future<void>? _encerrando;

  void _descarregar() {
    _ouvido = true;
    if (_eventos.isClosed) return;
    for (final e in _buffer) {
      _eventos.add(e);
    }
    _buffer.clear();
  }

  void _publicar(EventoServico e) {
    if (_eventos.isClosed) return;
    if (_ouvido && _buffer.isEmpty) {
      _eventos.add(e);
    } else {
      _buffer.add(e);
      if (_buffer.length > _limiteBuffer) _buffer.removeAt(0);
    }
  }

  void _tratar(List<Object?> m) {
    switch (m[0]) {
      case 'res':
        _pendentes.remove(m[1])?.complete(m[2]);
      case 'err':
        _pendentes
            .remove(m[1])
            ?.completeError(m[2]!, StackTrace.fromString(m[3] as String));
      case 'ev':
        _publicar(m[1] as EventoServico);
      case 'url':
        unawaited(_abrir(m[1] as int, m[2] as Uri));
    }
  }

  Future<void> _abrir(int id, Uri url) async {
    var abriu = false;
    try {
      abriu = await _abrirUrl(url);
    } catch (_) {
      // sem como abrir: o isolate transforma em ErroGoogle
    }
    if (_aberto) _enviar.send(['url', id, abriu]);
  }

  void _fechar() {
    if (!_aberto) return;
    _aberto = false;
    _isolate.kill(priority: Isolate.immediate);
    _recebe.close();
    _saida.close();
    for (final c in _pendentes.values) {
      c.completeError(StateError(_msgEncerrado));
    }
    _pendentes.clear();
    unawaited(_eventos.close());
  }

  /// A função enviada não captura o proxy (ele guarda portas, que não viajam):
  /// cada método passa uma função anônima que usa só os próprios parâmetros.
  Future<T> _chamar<T>(FutureOr<T> Function(ServicosApp) funcao) async {
    if (!_aberto) throw StateError(_msgEncerrado);
    final id = _proximo++;
    final resposta = _pendentes[id] = Completer<Object?>();
    try {
      _enviar.send(['chamar', id, funcao]);
    } catch (_) {
      // argumento não enviável: o pedido não saiu, não fica pendurado
      _pendentes.remove(id);
      rethrow;
    }
    return await resposta.future as T;
  }

  @override
  Stream<EventoServico> get eventos => _eventos.stream;

  // ciclo e preferências
  @override
  Future<EstadoInicial> iniciar() => _chamar((s) => s.iniciar());

  @override
  Future<void> encerrar() => _encerrando ??= _encerrar();

  Future<void> _encerrar() async {
    if (!_aberto) return;
    try {
      await _chamar((s) => s.encerrar());
    } on StateError {
      // o isolate morreu durante o encerramento: já está encerrado
      if (_aberto) rethrow;
    } finally {
      _fechar();
    }
  }

  @override
  Future<void> salvarPreferencias(Preferencias p) =>
      _chamar((s) => s.salvarPreferencias(p));

  // apuração
  @override
  Future<List<String>> mesesComDados({String? amigo}) =>
      _chamar((s) => s.mesesComDados(amigo: amigo));

  @override
  Future<String> mesInicial({String? amigo}) =>
      _chamar((s) => s.mesInicial(amigo: amigo));

  @override
  Future<VisaoMes> carregarMes(String mes, {String? amigo}) =>
      _chamar((s) => s.carregarMes(mes, amigo: amigo));

  @override
  Future<VisaoPosicoes> posicoes(String mes, {String? amigo}) =>
      _chamar((s) => s.posicoes(mes, amigo: amigo));

  @override
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) => _chamar((s) => s.sugestoesTicker(mes, soCustodia: soCustodia));

  @override
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) =>
      _chamar((s) => s.registrarCompra(mes, c));

  @override
  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c) =>
      _chamar((s) => s.editarCompra(mes, loteId, c));

  @override
  Future<VisaoMes> excluirCompra(String mes, String loteId) =>
      _chamar((s) => s.excluirCompra(mes, loteId));

  @override
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) =>
      _chamar((s) => s.registrarVenda(mes, v));

  @override
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) =>
      _chamar((s) => s.editarVenda(mes, vendaId, v));

  @override
  Future<VisaoMes> excluirVenda(String mes, String vendaId) =>
      _chamar((s) => s.excluirVenda(mes, vendaId));

  @override
  Future<String> novoGrupoVenda() => _chamar((s) => s.novoGrupoVenda());

  @override
  Future<List<Lote>> comprasElegiveis(String mes, String ticker, String data) =>
      _chamar((s) => s.comprasElegiveis(mes, ticker, data));

  @override
  Future<PreviaVenda> previaVenda(String mes, NovaVendaQtd v) =>
      _chamar((s) => s.previaVenda(mes, v));

  @override
  Future<VendaRegistrada> registrarVendaQtd(String mes, NovaVendaQtd v) =>
      _chamar((s) => s.registrarVendaQtd(mes, v));

  @override
  Future<VisaoMes> editarGrupoVenda(String mes, String grupo, NovaVendaQtd v) =>
      _chamar((s) => s.editarGrupoVenda(mes, grupo, v));

  @override
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) =>
      _chamar((s) => s.mesesSemVendaRetroativa(mesAtual));

  @override
  Future<int> reservadoEmMetas(String loteId) =>
      _chamar((s) => s.reservadoEmMetas(loteId));

  @override
  Future<PreparoFechamento> prepararFechamento(String mes) =>
      _chamar((s) => s.prepararFechamento(mes));

  @override
  Future<Fechamento> fecharMes(String mes) => _chamar((s) => s.fecharMes(mes));

  // caixa
  @override
  Future<VisaoCaixa> caixa({String? amigo}) =>
      _chamar((s) => s.caixa(amigo: amigo));

  @override
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) =>
      _chamar((s) => s.alterarSaldo(modo, valor));

  // conta, sincronização e amigos
  @override
  Future<EstadoConta> conta() => _chamar((s) => s.conta());

  @override
  Future<void> conectar() => _chamar((s) => s.conectar());

  @override
  Future<void> cancelarLogin() => _chamar((s) => s.cancelarLogin());

  @override
  Future<void> sair() => _chamar((s) => s.sair());

  @override
  Future<void> sincronizarAgora() => _chamar((s) => s.sincronizarAgora());

  @override
  Future<List<Amigo>> amigos() => _chamar((s) => s.amigos());

  @override
  Future<void> adicionarAmigo(String email) =>
      _chamar((s) => s.adicionarAmigo(email));

  @override
  Future<void> removerAmigo(String email) =>
      _chamar((s) => s.removerAmigo(email));

  @override
  Future<ResumoAmigo> carregarAmigo(String email) =>
      _chamar((s) => s.carregarAmigo(email));

  @override
  Future<void> esquecerAmigo() => _chamar((s) => s.esquecerAmigo());

  // mercado, radar e metas
  @override
  Future<VisaoRadar> radar({String? amigo}) =>
      _chamar((s) => s.radar(amigo: amigo));

  @override
  Future<ItemRadar> adicionarRadar(String ticker) =>
      _chamar((s) => s.adicionarRadar(ticker));

  @override
  Future<int> importarRadar(List<ItemRadar> itens) =>
      _chamar((s) => s.importarRadar(itens));

  @override
  Future<void> removerRadar(String ticker) =>
      _chamar((s) => s.removerRadar(ticker));

  @override
  Future<void> reordenarRadar(List<String> tickers) =>
      _chamar((s) => s.reordenarRadar(tickers));

  @override
  Future<void> limparCacheCotacoes() => _chamar((s) => s.limparCacheCotacoes());

  @override
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) =>
      _chamar((s) => s.cotacao(ticker, nome: nome));

  @override
  Future<Grafico> grafico(String ticker, String periodo) =>
      _chamar((s) => s.grafico(ticker, periodo));

  @override
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) =>
      _chamar((s) => s.precosCarteira(tickers));

  @override
  Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers) =>
      _chamar((s) => s.cotacoesAtuais(tickers));

  @override
  Future<(double, String)> precoVenda(String ticker, String dia) =>
      _chamar((s) => s.precoVenda(ticker, dia));

  @override
  Future<VisaoMetas> metas() => _chamar((s) => s.metas());

  @override
  Future<VisaoSugestoes> sugestoesMetas({bool incluirRadar = false}) =>
      _chamar((s) => s.sugestoesMetas(incluirRadar: incluirRadar));

  @override
  Future<PrecoAlvo> calcularPrecoAlvo(String loteId, int qtd, double lucro) =>
      _chamar((s) => s.calcularPrecoAlvo(loteId, qtd, lucro));

  @override
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) =>
      _chamar((s) => s.projetarPreco(loteId, qtd, preco));

  @override
  Future<Meta?> parceiraOco(String loteId, String gatilho) =>
      _chamar((s) => s.parceiraOco(loteId, gatilho));

  @override
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) => _chamar(
    (s) => s.criarMetaAlvo(
      loteId,
      qtd,
      precoAlvo,
      lucroDesejado: lucroDesejado,
      ocoCom: ocoCom,
    ),
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
  }) => _chamar(
    (s) => s.criarStop(
      loteId,
      qtd,
      precoStop,
      movel: movel,
      ocoCom: ocoCom,
      precoAtual: precoAtual,
      sugestao: sugestao,
    ),
  );

  @override
  Future<void> cancelarMeta(String metaId) =>
      _chamar((s) => s.cancelarMeta(metaId));

  @override
  Future<ResultadoVerificacao> verificarMetas() =>
      _chamar((s) => s.verificarMetas());

  // notícias, imagens e atualizador
  @override
  Future<VisaoNoticias> noticias() => _chamar((s) => s.noticias());

  @override
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) =>
      _chamar((s) => s.atualizarNoticias(forcar: forcar));

  @override
  Future<void> marcarNoticiasLidas() => _chamar((s) => s.marcarNoticiasLidas());

  @override
  Future<ImagemBytes?> logo(String ticker) => _chamar((s) => s.logo(ticker));

  @override
  Future<Uint8List?> favicon(Noticia item) => _chamar((s) => s.favicon(item));

  @override
  Future<Uint8List?> imagemNoticia(String url) =>
      _chamar((s) => s.imagemNoticia(url));

  @override
  Future<InfoAtualizacao?> verificarAtualizacao() =>
      _chamar((s) => s.verificarAtualizacao());

  @override
  Future<String> baixarAtualizacao(InfoAtualizacao info) =>
      _chamar((s) => s.baixarAtualizacao(info));

  @override
  Future<void> cancelarDownload() => _chamar((s) => s.cancelarDownload());
}
