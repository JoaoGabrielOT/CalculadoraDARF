// Serviços falsos para os testes de tela: respostas nos campos públicos,
// chamadas gravadas em [chamadas] e erro programável por método. As tarefas
// seguintes completam o que as telas delas usam; um método ainda sem
// resposta registra a chamada e lança `UnimplementedError`.

import 'dart:async';

import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
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
  Future<VisaoMes> excluirCompra(String mes, String loteId) =>
      _chamar('excluirCompra', [mes, loteId], () => _visao(mes));

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

  @override
  Future<VisaoMetas> metas() => _chamar(
    'metas',
    [],
    () => VisaoMetas(
      metas: [],
      descricoes: {},
      lotes: [],
      ativas: metasAtivasFalsas,
    ),
  );

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

  @override
  Future<void> adicionarAmigo(String email) => _chamar(
    'adicionarAmigo',
    [email],
    () {
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
