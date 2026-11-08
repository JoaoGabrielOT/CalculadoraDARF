// Serviços falsos para os testes de tela: respostas nos campos públicos,
// chamadas gravadas em [chamadas] e erro programável por método. As tarefas
// seguintes completam o que as telas delas usam; um método ainda sem
// resposta registra a chamada e lança `UnimplementedError`.

import 'dart:async';
import 'dart:typed_data';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';

import 'dados_exemplo.dart';

class ServicosFalsos implements ServicosApp {
  /// Nome do método e argumentos, na ordem das chamadas
  /// (por exemplo `registrarCompra(2026-10, PETR4)`).
  final List<String> chamadas = [];

  final StreamController<EventoServico> eventosFalsos =
      StreamController<EventoServico>.broadcast();

  /// Nome do método -> erro lançado (como `Future.error`) no lugar da resposta.
  final Map<String, Object> erros = {};

  // ciclo e preferências
  EstadoInicial? estadoInicial;
  Preferencias? preferenciasSalvas;

  // apuração
  List<String> meses = ['2026-09', '2026-10'];
  String mesAberto = '2026-10';
  Map<String, VisaoMes> visoes = {
    '2026-09': visaoExemplo(mesFechadoExemplo()),
    '2026-10': visaoExemplo(mesAbertoExemplo()),
  };
  SugestoesTicker sugestoes = const SugestoesTicker(
    tickers: ['PETR4', 'VALE3'],
    tipos: {'PETR4': 'Ação', 'VALE3': 'Ação'},
  );
  VendaRegistrada? vendaRegistrada;

  /// Últimos argumentos recebidos pelas gravações, para os testes conferirem.
  NovaCompra? ultimaCompra;
  NovaVenda? ultimaVenda;
  ({ModoSaldo modo, double valor})? ultimoSaldo;

  /// Quando preenchido, as gravações (compra e venda) só respondem depois dele;
  /// a chamada já fica registrada em [chamadas].
  Future<void>? esperaGravacao;

  /// Idem para `excluirCompra`.
  Future<void>? esperaExclusao;

  /// Idem para `reservadoEmMetas`.
  Future<void>? esperaReserva;

  /// Quando preenchido, `carregarMes` responde por ele (para deixar o
  /// `Future` pendente).
  Future<VisaoMes> Function(String mes, String? amigo)? carregarMesFn;

  /// Resposta de `registrarCompra` no lugar da visão do mês (traz o lote novo).
  VisaoMes? visaoAposCompra;

  /// Resposta de `prepararFechamento`; [preparoFn] tem precedência.
  PreparoFechamento? preparo;
  Future<PreparoFechamento> Function(String mes)? preparoFn;

  /// Quantas metas ativas `metas()` informa.
  int metasAtivasFalsas = 0;

  Future<T> _segurar<T>(Future<T> resposta, Future<void>? espera) async {
    if (espera != null) await espera;
    return resposta;
  }

  /// Resposta de `precoVenda`; nula = falha. [precoVendaFn] tem precedência
  /// (para deixar o `Future` pendente).
  (double, String)? precoVendaResp;
  Future<(double, String)> Function(String ticker, String dia)? precoVendaFn;
  Fechamento? fechamento;
  Set<String> semVendaRetroativa = {};
  int reservadoMetas = 0;

  /// Resposta de `precosCarteira`: ticker ausente = ainda sem tentar; valor
  /// nulo = tentou e falhou. [precosFn] tem precedência (para deixar o
  /// `Future` pendente).
  Map<String, double?> precos = {};
  Future<Map<String, double?>> Function(Set<String> tickers)? precosFn;

  /// Resposta de `posicoes` por mês; sem ela, as posições saem dos meses de
  /// [visoes] pelo núcleo (como o serviço real). [posicoesFn] tem
  /// precedência (para deixar o `Future` pendente).
  Map<String, VisaoPosicoes> posicoesPorMes = {};
  Future<VisaoPosicoes> Function(String mes, String? amigo)? posicoesFn;

  /// Resposta de `cotacoesAtuais`: ticker ausente = sem cotação (nulo).
  /// [cotacoesAtuaisFn] tem precedência.
  Map<String, CotacaoAtual?> cotacoesAtuaisResp = {};
  Future<Map<String, CotacaoAtual?>> Function(Set<String> tickers)?
  cotacoesAtuaisFn;

  // caixa
  VisaoCaixa? visaoCaixa;

  Future<T> _chamar<T>(String nome, List<Object?> args, T Function() resposta) {
    chamadas.add('$nome(${args.join(', ')})');
    final erro = erros[nome];
    if (erro != null) return Future<T>.error(erro);
    return Future<T>.sync(resposta);
  }

  VisaoMes _visao(String mes) => visoes[mes] ?? visaoExemplo(mesVazio(mes));

  @override
  Stream<EventoServico> get eventos => eventosFalsos.stream;

  @override
  Future<EstadoInicial> iniciar() => _chamar(
    'iniciar',
    [],
    () =>
        estadoInicial ??
        EstadoInicial(
          mesInicial: mesAberto,
          mesesComDados: meses,
          preferencias: const Preferencias(),
        ),
  );

  @override
  Future<void> encerrar() => _chamar('encerrar', [], () {});

  @override
  Future<void> salvarPreferencias(Preferencias p) =>
      _chamar('salvarPreferencias', [p.tema.chave], () {
        preferenciasSalvas = p;
      });

  @override
  Future<List<String>> mesesComDados({String? amigo}) =>
      _chamar('mesesComDados', [amigo], () => meses);

  @override
  Future<String> mesInicial({String? amigo}) =>
      _chamar('mesInicial', [amigo], () => mesAberto);

  @override
  Future<VisaoMes> carregarMes(String mes, {String? amigo}) {
    final fn = carregarMesFn;
    if (fn != null) {
      chamadas.add('carregarMes($mes, $amigo)');
      return fn(mes, amigo);
    }
    return _chamar('carregarMes', [mes, amigo], () {
      final v = _visao(mes);
      if (amigo == null || v.amigo == amigo) return v;
      return VisaoMes(
        mes: v.mes,
        dados: v.dados,
        apuracao: v.apuracao,
        amigo: amigo,
        erroLeitura: v.erroLeitura,
      );
    });
  }

  @override
  Future<VisaoPosicoes> posicoes(String mes, {String? amigo}) {
    final fn = posicoesFn;
    if (fn != null) {
      chamadas.add('posicoes($mes, $amigo)');
      return fn(mes, amigo);
    }
    return _chamar('posicoes', [mes, amigo], () {
      final pronta = posicoesPorMes[mes];
      if (pronta != null) return pronta;
      final hoje = ambiente.hoje();
      final corte = dataCorteDoMes(mes, hoje);
      final dados = {for (final e in visoes.entries) e.key: e.value.dados};
      return VisaoPosicoes(
        dataCorte: corte,
        corrente: corte == hoje,
        posicoes: posicoesEm(dados, corte),
      );
    });
  }

  @override
  Future<Map<String, CotacaoAtual?>> cotacoesAtuais(Set<String> tickers) {
    final lista = tickers.toList()..sort();
    final fn = cotacoesAtuaisFn;
    if (fn != null) {
      chamadas.add('cotacoesAtuais(${lista.join(',')})');
      return fn(tickers);
    }
    return _chamar('cotacoesAtuais', [
      lista.join(','),
    ], () => {for (final t in tickers) t: cotacoesAtuaisResp[t]});
  }

  @override
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) => _chamar('sugestoesTicker', [mes, soCustodia], () => sugestoes);

  @override
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) => _segurar(
    _chamar('registrarCompra', [mes, c.ticker], () {
      ultimaCompra = c;
      return visaoAposCompra ?? _visao(mes);
    }),
    esperaGravacao,
  );

  @override
  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c) =>
      _segurar(
        _chamar('editarCompra', [mes, loteId, c.ticker], () {
          ultimaCompra = c;
          return _visao(mes);
        }),
        esperaGravacao,
      );

  @override
  Future<Map<String, double?>> precosCarteira(Set<String> tickers) {
    final lista = tickers.toList()..sort();
    final fn = precosFn;
    if (fn != null) {
      chamadas.add('precosCarteira(${lista.join(',')})');
      return fn(tickers);
    }
    return _chamar(
      'precosCarteira',
      [lista.join(',')],
      () => {
        for (final t in tickers)
          if (precos.containsKey(t)) t: precos[t],
      },
    );
  }

  @override
  Future<VisaoMes> excluirCompra(String mes, String loteId) => _segurar(
    _chamar('excluirCompra', [mes, loteId], () => _visao(mes)),
    esperaExclusao,
  );

  @override
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) => _segurar(
    _chamar('registrarVenda', [mes, v.loteId, v.data, v.qtd], () {
      ultimaVenda = v;
      return vendaRegistrada ?? VendaRegistrada(visao: _visao(mes));
    }),
    esperaGravacao,
  );

  @override
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) =>
      _segurar(
        _chamar('editarVenda', [mes, vendaId, v.data, v.qtd], () {
          ultimaVenda = v;
          return _visao(mes);
        }),
        esperaGravacao,
      );

  @override
  Future<VisaoMes> excluirVenda(String mes, String vendaId) =>
      _chamar('excluirVenda', [mes, vendaId], () => _visao(mes));

  @override
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) =>
      _chamar('mesesSemVendaRetroativa', [mesAtual], () => semVendaRetroativa);

  @override
  Future<(double, String)> precoVenda(String ticker, String dia) {
    chamadas.add('precoVenda($ticker, $dia)');
    final erro = erros['precoVenda'];
    if (erro != null) return Future.error(erro);
    final fn = precoVendaFn;
    if (fn != null) return fn(ticker, dia);
    final r = precoVendaResp;
    return r == null ? Future.error(Exception('sem cotação')) : Future.value(r);
  }

  @override
  Future<int> reservadoEmMetas(String loteId) => _segurar(
    _chamar('reservadoEmMetas', [loteId], () => reservadoMetas),
    esperaReserva,
  );

  @override
  Future<PreparoFechamento> prepararFechamento(String mes) {
    final fn = preparoFn;
    if (fn != null) {
      chamadas.add('prepararFechamento($mes)');
      return fn(mes);
    }
    return _chamar('prepararFechamento', [
      mes,
    ], () => preparo ?? PreparoFechamento());
  }

  /// Resposta de `metas`; sem ela, uma visão vazia com [metasAtivasFalsas].
  VisaoMetas? visaoMetas;

  /// Quando preenchido, `verificarMetas` responde por ele (para deixar o
  /// `Future` pendente); sem ele, devolve [resultadoVerificacao].
  Future<ResultadoVerificacao> Function()? verificarMetasFn;
  ResultadoVerificacao resultadoVerificacao = const SemMetasAtivas();

  /// Respostas de `calcularPrecoAlvo` e `projetarPreco` (por preço).
  PrecoAlvo? precoAlvo;
  Projecao Function(double preco)? projecaoFn;

  /// Últimos argumentos de `criarMetaAlvo`.
  ({String loteId, int qtd, double preco, double? lucro})? ultimaMetaAlvo;

  /// `ocoCom` da última chamada de `criarMetaAlvo`.
  String? ultimoOcoAlvo;

  /// Resposta de `sugestoesMetas`; [sugestoesMetasFn] tem precedência.
  VisaoSugestoes? visaoSugestoes;
  Future<VisaoSugestoes> Function()? sugestoesMetasFn;

  /// Resposta de `parceiraOco` (por gatilho); sem entrada = sem parceira.
  Map<String, Meta?> parceirasOco = {};

  /// Últimos argumentos de `criarStop`.
  ({
    String loteId,
    int qtd,
    double preco,
    bool movel,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  })?
  ultimoStop;

  @override
  Future<VisaoSugestoes> sugestoesMetas() {
    final fn = sugestoesMetasFn;
    if (fn != null) {
      chamadas.add('sugestoesMetas()');
      return fn();
    }
    return _chamar(
      'sugestoesMetas',
      [],
      () => visaoSugestoes ?? const VisaoSugestoes(itens: [], rodape: []),
    );
  }

  @override
  Future<Meta?> parceiraOco(String loteId, String gatilho) =>
      _chamar('parceiraOco', [loteId, gatilho], () => parceirasOco[gatilho]);

  @override
  Future<Meta> criarStop(
    String loteId,
    int qtd,
    double precoStop, {
    bool movel = false,
    String? ocoCom,
    double? precoAtual,
    Map<String, Object?>? sugestao,
  }) => _chamar('criarStop', [loteId, qtd, precoStop, movel], () {
    ultimoStop = (
      loteId: loteId,
      qtd: qtd,
      preco: precoStop,
      movel: movel,
      ocoCom: ocoCom,
      precoAtual: precoAtual,
      sugestao: sugestao,
    );
    return metasExemplo().first;
  });

  @override
  Future<VisaoMetas> metas() => _chamar(
    'metas',
    [],
    () =>
        visaoMetas ??
        VisaoMetas(
          metas: [],
          descricoes: {},
          lotes: [],
          ativas: metasAtivasFalsas,
        ),
  );

  @override
  Future<PrecoAlvo> calcularPrecoAlvo(String loteId, int qtd, double lucro) =>
      _chamar('calcularPrecoAlvo', [loteId, qtd, lucro], () => precoAlvo!);

  @override
  Future<Projecao> projetarPreco(String loteId, int qtd, double preco) =>
      _chamar('projetarPreco', [loteId, qtd, preco], () => projecaoFn!(preco));

  @override
  Future<Meta> criarMetaAlvo(
    String loteId,
    int qtd,
    double precoAlvo, {
    double? lucroDesejado,
    String? ocoCom,
  }) => _chamar('criarMetaAlvo', [loteId, qtd, precoAlvo, lucroDesejado], () {
    ultimoOcoAlvo = ocoCom;
    ultimaMetaAlvo = (
      loteId: loteId,
      qtd: qtd,
      preco: precoAlvo,
      lucro: lucroDesejado,
    );
    return metasExemplo().first;
  });

  @override
  Future<void> cancelarMeta(String metaId) =>
      _chamar('cancelarMeta', [metaId], () {});

  @override
  Future<ResultadoVerificacao> verificarMetas() {
    final fn = verificarMetasFn;
    if (fn != null) {
      chamadas.add('verificarMetas()');
      return fn();
    }
    return _chamar('verificarMetas', [], () => resultadoVerificacao);
  }

  @override
  Future<Fechamento> fecharMes(String mes) => _chamar(
    'fecharMes',
    [mes],
    () =>
        fechamento ??
        Fechamento(visao: _visao(mes), mensagem: 'Não há DARF a pagar.'),
  );

  @override
  Future<VisaoCaixa> caixa({String? amigo}) =>
      _chamar('caixa', [amigo], () => visaoCaixa ?? caixaExemplo());

  @override
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) =>
      _chamar('alterarSaldo', [modo.name, valor], () {
        ultimoSaldo = (modo: modo, valor: valor);
        return visaoCaixa ?? caixaExemplo();
      });

  // conta, sincronização e amigos
  EstadoConta estadoConta = const EstadoConta();
  List<Amigo> listaAmigos = [];
  ResumoAmigo? resumoAmigo;

  @override
  Future<EstadoConta> conta() => _chamar('conta', [], () => estadoConta);

  @override
  Future<void> conectar() => _chamar('conectar', [], () {});

  @override
  Future<void> cancelarLogin() => _chamar('cancelarLogin', [], () {});

  @override
  Future<void> sair() => _chamar('sair', [], () {});

  @override
  Future<void> sincronizarAgora() => _chamar('sincronizarAgora', [], () {});

  @override
  Future<List<Amigo>> amigos() => _chamar('amigos', [], () => listaAmigos);

  /// Quando preenchido, `adicionarAmigo` só responde depois dele.
  Future<void>? esperaAdicionarAmigo;

  @override
  Future<void> adicionarAmigo(String email) => _chamar(
    'adicionarAmigo',
    [email],
    () async {
      await esperaAdicionarAmigo;
      listaAmigos = [...listaAmigos, Amigo(email: email, desde: '2026-10-28')];
    },
  );

  @override
  Future<void> removerAmigo(String email) =>
      _chamar('removerAmigo', [email], () {
        listaAmigos = [
          for (final a in listaAmigos)
            if (a.email != email) a,
        ];
      });

  @override
  Future<ResumoAmigo> carregarAmigo(String email) => _chamar(
    'carregarAmigo',
    [email],
    () =>
        resumoAmigo ??
        ResumoAmigo(email: email, meses: meses, mesInicial: mesAberto),
  );

  @override
  Future<void> esquecerAmigo() => _chamar('esquecerAmigo', [], () {});

  // notícias
  VisaoNoticias visaoNoticias = const VisaoNoticias(
    itens: [],
    detalhes: {},
    naoLidas: 0,
    hora: 0,
    lidasAte: 0,
    erros: {},
    rodando: false,
    radar: [],
  );

  /// Quando preenchidos, `noticias`, `atualizarNoticias`, `favicon` e
  /// `imagemNoticia` respondem por eles (para deixar o `Future` pendente).
  Future<VisaoNoticias> Function()? noticiasFn;
  Future<VisaoNoticias> Function(bool forcar)? atualizarNoticiasFn;
  Future<Uint8List?> Function(Noticia item)? faviconFn;
  Future<Uint8List?> Function(String url)? imagemNoticiaFn;

  @override
  Future<VisaoNoticias> noticias() {
    chamadas.add('noticias()');
    final erro = erros['noticias'];
    if (erro != null) return Future.error(erro);
    return noticiasFn?.call() ?? Future.value(visaoNoticias);
  }

  @override
  Future<VisaoNoticias> atualizarNoticias({bool forcar = false}) {
    chamadas.add('atualizarNoticias($forcar)');
    final erro = erros['atualizarNoticias'];
    if (erro != null) return Future.error(erro);
    return atualizarNoticiasFn?.call(forcar) ?? Future.value(visaoNoticias);
  }

  @override
  Future<void> marcarNoticiasLidas() =>
      _chamar('marcarNoticiasLidas', [], () {});

  @override
  Future<Uint8List?> favicon(Noticia item) {
    chamadas.add('favicon(${item.id})');
    return faviconFn?.call(item) ?? Future.value();
  }

  @override
  Future<Uint8List?> imagemNoticia(String url) {
    chamadas.add('imagemNoticia($url)');
    return imagemNoticiaFn?.call(url) ?? Future.value();
  }

  // radar e cotações
  VisaoRadar visaoRadar = VisaoRadar(
    itens: radarExemplo(),
    custodia: {'PETR4'},
    meus: {'PETR4', 'WEGE3', 'MXRF11'},
  );

  /// Radar devolvido com `amigo != null`.
  VisaoRadar? visaoRadarAmigo;

  /// Resposta de `cotacao` por ticker; sem entrada, um erro de teste.
  /// [cotacaoFn] tem precedência (para deixar o `Future` pendente).
  Map<String, CotacaoRadar> cotacoesFalsas = {};
  Future<CotacaoRadar> Function(String ticker, String nome)? cotacaoFn;

  /// Gráfico do dia por ticker; sem entrada, um gráfico fixo.
  /// [graficoFn] tem precedência.
  Map<String, Grafico> graficosFalsos = {};
  Future<Grafico> Function(String ticker, String periodo)? graficoFn;
  List<String>? ultimaOrdemRadar;
  List<ItemRadar>? ultimaImportacao;

  @override
  Future<VisaoRadar> radar({String? amigo}) => _chamar('radar', [
    amigo,
  ], () => amigo == null ? visaoRadar : visaoRadarAmigo ?? visaoRadar);

  @override
  Future<ItemRadar> adicionarRadar(String ticker) =>
      _chamar('adicionarRadar', [ticker], () {
        final item = ItemRadar(
          ticker: ticker.trim().toUpperCase(),
          desde: hojeExemplo,
          pos: visaoRadar.itens.length,
        );
        visaoRadar = VisaoRadar(
          itens: [...visaoRadar.itens, item],
          custodia: visaoRadar.custodia,
          meus: {...visaoRadar.meus, item.ticker},
        );
        return item;
      });

  @override
  Future<int> importarRadar(List<ItemRadar> itens) =>
      _chamar('importarRadar', [itens.map((i) => i.ticker).join(',')], () {
        ultimaImportacao = itens;
        visaoRadar = VisaoRadar(
          itens: visaoRadar.itens,
          custodia: visaoRadar.custodia,
          meus: {...visaoRadar.meus, for (final i in itens) i.ticker},
        );
        final amigo = visaoRadarAmigo;
        if (amigo != null) {
          visaoRadarAmigo = VisaoRadar(
            itens: amigo.itens,
            custodia: amigo.custodia,
            meus: visaoRadar.meus,
            amigo: amigo.amigo,
          );
        }
        return itens.length;
      });

  @override
  Future<void> removerRadar(String ticker) =>
      _chamar('removerRadar', [ticker], () {
        visaoRadar = VisaoRadar(
          itens: [
            for (final i in visaoRadar.itens)
              if (i.ticker != ticker) i,
          ],
          custodia: visaoRadar.custodia,
          meus: {...visaoRadar.meus}..remove(ticker),
        );
      });

  @override
  Future<void> reordenarRadar(List<String> tickers) =>
      _chamar('reordenarRadar', [tickers.join(',')], () {
        ultimaOrdemRadar = tickers;
        final porTicker = {for (final i in visaoRadar.itens) i.ticker: i};
        visaoRadar = VisaoRadar(
          itens: [for (final t in tickers) porTicker[t]!],
          custodia: visaoRadar.custodia,
          meus: visaoRadar.meus,
        );
      });

  @override
  Future<void> limparCacheCotacoes() =>
      _chamar('limparCacheCotacoes', [], () {});

  @override
  Future<CotacaoRadar> cotacao(String ticker, {String nome = ''}) {
    chamadas.add('cotacao($ticker)');
    final erro = erros['cotacao'];
    if (erro != null) return Future.error(erro);
    final fn = cotacaoFn;
    if (fn != null) return fn(ticker, nome);
    final r = cotacoesFalsas[ticker];
    return r == null
        ? Future.error(Exception('sem cotação de $ticker'))
        : Future.value(r);
  }

  @override
  Future<Grafico> grafico(String ticker, String periodo) {
    chamadas.add('grafico($ticker, $periodo)');
    final erro = erros['grafico'];
    if (erro != null) return Future.error(erro);
    final fn = graficoFn;
    if (fn != null) return fn(ticker, periodo);
    return Future.value(
      graficosFalsos[ticker] ??
          Grafico(
            ticker: ticker,
            periodo: periodo,
            pontos: const [(1, 10.0), (2, 10.5), (3, 10.2), (4, 10.8)],
            referencia: 10,
            desvio: 0,
            intradiario: true,
          ),
    );
  }

  // atualizador
  InfoAtualizacao? infoAtualizacao;

  /// Caminho devolvido por `baixarAtualizacao`; [baixarFn] tem precedência
  /// (para deixar o `Future` pendente ou emitir progresso).
  String caminhoBaixado = '/tmp/CalculadoraDARF-9.9.9.exe';
  Future<String> Function(InfoAtualizacao info)? baixarFn;

  @override
  Future<InfoAtualizacao?> verificarAtualizacao() =>
      _chamar('verificarAtualizacao', [], () => infoAtualizacao);

  @override
  Future<String> baixarAtualizacao(InfoAtualizacao info) {
    chamadas.add('baixarAtualizacao(${info.versao})');
    final erro = erros['baixarAtualizacao'];
    if (erro != null) return Future.error(erro);
    return baixarFn?.call(info) ?? Future.value(caminhoBaixado);
  }

  @override
  Future<void> cancelarDownload() => _chamar('cancelarDownload', [], () {});

  /// Métodos das Tarefas 5 e 6 ainda sem resposta.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final nome = RegExp(r'"(.*)"')
        .firstMatch(invocation.memberName.toString())!
        .group(1);
    chamadas.add('$nome(${invocation.positionalArguments.join(', ')})');
    return Future<Never>.error(
      UnimplementedError('ServicosFalsos.$nome ainda não tem resposta.'),
    );
  }
}
