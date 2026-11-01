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
  Fechamento? fechamento;
  Set<String> semVendaRetroativa = {};
  int reservadoMetas = 0;

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
  Future<VisaoMes> carregarMes(String mes, {String? amigo}) =>
      _chamar('carregarMes', [mes, amigo], () => _visao(mes));

  @override
  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) => _chamar('sugestoesTicker', [mes, soCustodia], () => sugestoes);

  @override
  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) =>
      _chamar('registrarCompra', [mes, c.ticker], () => _visao(mes));

  @override
  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c) =>
      _chamar('editarCompra', [mes, loteId, c.ticker], () => _visao(mes));

  @override
  Future<VisaoMes> excluirCompra(String mes, String loteId) =>
      _chamar('excluirCompra', [mes, loteId], () => _visao(mes));

  @override
  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) => _chamar(
    'registrarVenda',
    [mes, v.loteId, v.data, v.qtd],
    () => vendaRegistrada ?? VendaRegistrada(visao: _visao(mes)),
  );

  @override
  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) =>
      _chamar('editarVenda', [mes, vendaId, v.data, v.qtd], () => _visao(mes));

  @override
  Future<VisaoMes> excluirVenda(String mes, String vendaId) =>
      _chamar('excluirVenda', [mes, vendaId], () => _visao(mes));

  @override
  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) =>
      _chamar('mesesSemVendaRetroativa', [mesAtual], () => semVendaRetroativa);

  @override
  Future<int> reservadoEmMetas(String loteId) =>
      _chamar('reservadoEmMetas', [loteId], () => reservadoMetas);

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
  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) => _chamar(
    'alterarSaldo',
    [modo.name, valor],
    () => visaoCaixa ?? caixaExemplo(),
  );

  /// Métodos das Tarefas 4 a 6 ainda sem resposta.
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
