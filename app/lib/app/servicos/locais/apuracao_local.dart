// Apuração, compras, vendas e caixa sobre o repositório local. Cada mutação
// é síncrona do começo ao fim: relê o disco, valida, grava, agenda a
// sincronização e emite o evento, sem `await` no meio (o isolate tem um só
// laço de eventos, então ela é atômica em relação à sincronização).

import '../../../nucleo/nucleo.dart';
import '../../../nucleo/nucleo.dart' as nc;
import '../api.dart';
import '../eventos.dart';
import 'config_segura.dart';

/// Dados do amigo carregado (somente leitura).
typedef AmigoCarregado = ({String email, DadosPlanilha dados});

bool _erroDeLeitura(Object e) =>
    e is FormatException ||
    e is TypeError ||
    e is RangeError ||
    e is ErroNucleo;

const _mesFechado = 'O mês está fechado.';
const _dataVendaInvalida = 'Data da venda inválida para essa compra.';

String _mensagemMes(String mes) =>
    'Não foi possível ler o mês ${fmtMes(mes)}. '
    'Confira os valores gravados no arquivo $mes.json.';

/// Data `AAAA-MM-DD` válida, ou nulo.
String? _dataIso(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  try {
    return somarDias(s, 0);
  } on FormatException {
    return null;
  }
}

class ApuracaoLocal {
  ApuracaoLocal(
    this.repo, {
    required this.agendarSync,
    required this.emitir,
    this.amigoAtual,
  });

  final Repositorio repo;
  final void Function() agendarSync;
  final void Function(EventoServico) emitir;

  /// Amigo carregado pela conta (Tarefa 4); nulo quando não há.
  final AmigoCarregado? Function()? amigoAtual;

  // --- leitura

  Mes _lerMes(String mes) {
    try {
      return repo.carregar(mes);
    } catch (e) {
      if (_erroDeLeitura(e)) throw ErroValidacao(_mensagemMes(mes));
      rethrow;
    }
  }

  Map<String, Mes> _carregarTodos() => {
    for (final m in repo.listarMeses()) m: _lerMes(m),
  };

  DadosPlanilha _dadosAmigo(String email) {
    final a = amigoAtual?.call();
    if (a == null || a.email != email) {
      throw ErroValidacao('Os dados de $email não estão carregados.');
    }
    return a.dados;
  }

  VisaoMes _visaoDe(String mes, Mes d, {String? amigo}) {
    try {
      return VisaoMes(mes: mes, dados: d, apuracao: apurar(d), amigo: amigo);
    } catch (e) {
      if (!_erroDeLeitura(e)) rethrow;
      return _visaoComErro(mes, _mensagemMes(mes), amigo: amigo);
    }
  }

  VisaoMes _visaoComErro(String mes, String erro, {String? amigo}) {
    final vazio = mesVazio(mes);
    return VisaoMes(
      mes: mes,
      dados: vazio,
      apuracao: apurar(vazio),
      amigo: amigo,
      erroLeitura: erro,
    );
  }

  String _mesDeHoje() => ambiente.hoje().substring(0, 7);

  Future<List<String>> mesesComDados({String? amigo}) async {
    if (amigo != null) {
      return ordenadoPor(_dadosAmigo(amigo).meses.keys, (m) => [m]);
    }
    return repo.listarMeses();
  }

  Future<String> mesInicial({String? amigo}) async =>
      mesInicialSync(amigo: amigo);

  /// Primeiro mês aberto; um mês ilegível conta como aberto para a tela
  /// mostrar o aviso (`Repositorio.mesInicial` lançaria).
  String mesInicialSync({String? amigo}) {
    if (amigo != null) {
      final meses = _dadosAmigo(amigo).meses;
      final abertos = ordenadoPor([
        for (final e in meses.entries)
          if (!e.value.fechado) e.key,
      ], (m) => [m]);
      if (abertos.isNotEmpty) return abertos.first;
      if (meses.isEmpty) return _mesDeHoje();
      return ordenadoPor(meses.keys, (m) => [m]).last;
    }
    for (final m in repo.listarMeses()) {
      try {
        if (!repo.carregar(m).fechado) return m;
      } catch (e) {
        if (!_erroDeLeitura(e)) rethrow;
        return m;
      }
    }
    return _mesDeHoje();
  }

  /// Posições em aberto no fim de [mes] (ou hoje, no mês de hoje). Só lê: um
  /// mês sem arquivo não é criado.
  Future<VisaoPosicoes> posicoes(String mes, {String? amigo}) async {
    final meses = amigo != null ? _dadosAmigo(amigo).meses : _carregarTodos();
    final hoje = ambiente.hoje();
    final corte = dataCorteDoMes(mes, hoje);
    final posicoes = posicoesEm(meses, corte);
    return VisaoPosicoes(
      dataCorte: corte,
      corrente: corte == hoje,
      posicoes: posicoes,
      indicadores: indicadoresPorAtivo(
        meses: meses,
        mes: mes,
        posicao: posicoes,
      ),
    );
  }

  Future<VisaoMes> carregarMes(String mes, {String? amigo}) async {
    if (amigo != null) {
      final d = _dadosAmigo(amigo).meses[mes] ?? mesVazio(mes);
      return _visaoDe(mes, d, amigo: amigo);
    }
    try {
      return _visaoDe(mes, _lerMes(mes));
    } on ErroValidacao catch (e) {
      return _visaoComErro(mes, e.mensagem);
    }
  }

  Future<SugestoesTicker> sugestoesTicker(
    String mes, {
    bool soCustodia = false,
  }) async {
    final d = _lerMes(mes);
    try {
      final (tickers, tipos) = sugestoesTickers(
        repo,
        d,
        soCustodia: soCustodia,
      );
      return SugestoesTicker(tickers: tickers, tipos: tipos);
    } catch (e) {
      if (_erroDeLeitura(e)) {
        throw ErroValidacao('Não foi possível ler os meses salvos.');
      }
      rethrow;
    }
  }

  Future<Set<String>> mesesSemVendaRetroativa(String mesAtual) async {
    final saida = <String>{};
    for (final m in repo.listarMeses()) {
      if (compararTexto(m, mesAtual) >= 0) continue;
      try {
        if (!mesAceitaVendaRetroativa(repo, m, mesAtual)) saida.add(m);
      } catch (e) {
        if (!_erroDeLeitura(e)) rethrow;
        saida.add(m);
      }
    }
    return saida;
  }

  Future<int> reservadoEmMetas(String loteId) async {
    final cfg = lerConfigParaGravar(repo);
    return reservado(repo, cfg, loteId, meses: _carregarTodos());
  }

  // --- mutações

  Mes _mesEditavel(String mes) {
    final d = _lerMes(mes);
    if (d.fechado) throw ErroValidacao(_mesFechado);
    return d;
  }

  void _gravou() {
    agendarSync();
    emitir(const EventoDadosMudaram());
  }

  /// Valida o que o `FormCompra` valida (calculadora_darf.py:279-300).
  Lote _novaCompra(String id, NovaCompra c) {
    final ticker = c.ticker.trim().toUpperCase();
    if (ticker.isEmpty) throw ErroValidacao('Informe o ticker.');
    final data = _dataIso(c.dataCompra);
    if (data == null) throw ErroValidacao('Selecione a data da compra.');
    if (data.compareTo(ambiente.hoje()) > 0) {
      throw ErroValidacao('A data da compra não pode ser futura.');
    }
    if (c.qtd <= 0) throw ErroValidacao('Quantidade inválida.');
    if (!(c.preco > 0) || c.preco.isInfinite) {
      throw ErroValidacao('Preço inválido.');
    }
    return Lote(
      id: id,
      ticker: ticker,
      tipo: tipoPorTicker(ticker),
      dataCompra: data,
      qtd: c.qtd,
      preco: c.preco,
    );
  }

  Lote _acharLote(Mes d, String loteId) {
    for (final l in d.lotes) {
      if (l.id == loteId) return l;
    }
    throw ErroValidacao('Compra não encontrada.');
  }

  Future<VisaoMes> registrarCompra(String mes, NovaCompra c) async {
    final d = _mesEditavel(mes);
    d.lotes.add(_novaCompra(ambiente.novoId(), c));
    repo.salvar(d);
    _gravou();
    return _visaoDe(mes, d);
  }

  Future<VisaoMes> editarCompra(String mes, String loteId, NovaCompra c) async {
    final d = _mesEditavel(mes);
    final lote = _acharLote(d, loteId);
    final novo = _novaCompra(lote.id, c);
    novo.vendas = lote.vendas;
    final msg = erroEdicaoLote(lote, novo);
    if (msg != null) throw ErroValidacao(msg);
    lote
      ..ticker = novo.ticker
      ..tipo = novo.tipo
      ..dataCompra = novo.dataCompra
      ..qtd = novo.qtd
      ..preco = novo.preco;
    repo.salvar(d);
    _gravou();
    return _visaoDe(mes, d);
  }

  Future<VisaoMes> excluirCompra(String mes, String loteId) async {
    final d = _mesEditavel(mes);
    _acharLote(d, loteId);
    d.lotes = [
      for (final l in d.lotes)
        if (l.id != loteId) l,
    ];
    repo.salvar(d);
    _gravou();
    return _visaoDe(mes, d);
  }

  /// Validações do `FormVenda` (calculadora_darf.py:502-532) sobre o disco
  /// relido. [lote] já vem sem a venda editada, quando for edição.
  /// Venda de mês anterior ao aberto só vale em [edicao] falsa e em mês que
  /// aceita venda retroativa.
  ({String data, int qtd, double preco}) _validarVenda(
    String mes,
    Lote lote,
    NovaVenda v, {
    required bool edicao,
  }) {
    final data = _dataIso(v.data);
    if (data == null) throw ErroValidacao('Selecione a data da venda.');
    final mesVenda = data.substring(0, 7);
    var permitida =
        data.compareTo(ambiente.hoje()) <= 0 &&
        compararTexto(mesVenda, mes) <= 0 &&
        data.compareTo(lote.dataCompra) >= 0;
    if (permitida && compararTexto(mesVenda, mes) < 0) {
      try {
        permitida = !edicao && mesAceitaVendaRetroativa(repo, mesVenda, mes);
      } catch (e) {
        if (!_erroDeLeitura(e)) rethrow;
        throw ErroValidacao(_mensagemMes(mesVenda));
      }
    }
    if (!permitida) throw ErroValidacao(_dataVendaInvalida);
    if (v.qtd <= 0) throw ErroValidacao('Quantidade inválida.');
    final disp = restante(lote);
    if (v.qtd > disp) {
      throw ErroValidacao('Quantidade maior que a disponível ($disp).');
    }
    if (!(v.preco > 0) || v.preco.isInfinite) {
      throw ErroValidacao('Preço inválido.');
    }
    return (data: data, qtd: v.qtd, preco: v.preco);
  }

  Future<VendaRegistrada> registrarVenda(String mes, NovaVenda v) async {
    final d = _mesEditavel(mes);
    Lote? lote;
    for (final l in d.lotes) {
      if (l.id == v.loteId) lote = l;
    }
    if (lote == null) {
      throw ErroValidacao('Escolha o ticker e a compra que foi vendida.');
    }
    final venda = _validarVenda(mes, lote, v, edicao: false);
    if (compararTexto(venda.data.substring(0, 7), mes) >= 0) {
      lote.vendas.add(
        Venda(
          id: ambiente.novoId(),
          data: venda.data,
          qtd: venda.qtd,
          preco: venda.preco,
        ),
      );
      repo.salvar(d);
      _gravou();
      return VendaRegistrada(visao: _visaoDe(mes, d));
    }

    if (lote.vendas.isNotEmpty) {
      throw ErroValidacao(
        'Essa compra já tem venda neste mês. Para registrar uma venda de mês '
        'anterior, exclua a venda deste mês, registre a antiga e depois '
        'registre de novo a deste mês.',
      );
    }
    final livre =
        restante(lote) -
        reservado(
          repo,
          lerConfigParaGravar(repo),
          lote.id,
          meses: _carregarTodos(),
        );
    if (venda.qtd > livre) {
      throw ErroValidacao(
        'Há metas de venda ativas nessa compra. Quantidade livre: '
        '${livre > 0 ? livre : 0}. Cancele ou ajuste a meta antes.',
      );
    }
    final gravado = registrarVendaRetroativa(repo, d, lote.id, venda);
    final darf = repo.carregar(gravado).resumo?.darf ?? 0.0;
    _gravou();
    return VendaRegistrada(
      visao: _visaoDe(mes, d),
      mesGravado: gravado,
      aviso: _avisoRetroativa(gravado, mes, darf),
    );
  }

  /// Texto de calculadora_darf.py:1656-1676.
  String _avisoRetroativa(String gravado, String mes, double darf) {
    final String txtDarf;
    if (darf >= darfMinimo) {
      final venc = proximoMes(gravado);
      final prazo = compararTexto(venc, _mesDeHoje()) < 0
          ? 'já vencida: pague com multa e juros'
          : 'vence no último dia útil de ${fmtMes(venc)}';
      txtDarf =
          'DARF de ${fmtMes(gravado)}: ${brl(darf)} (código 6015, $prazo).';
    } else if (darf > 0) {
      txtDarf =
          'A DARF de ${brl(darf)} é menor que R\$ 10 e foi somada a '
          '${fmtMes(mes)}.';
    } else {
      txtDarf = 'Não há DARF a pagar por essa venda.';
    }
    return 'A venda foi gravada em ${fmtMes(gravado)}, que ficou fechado com a '
        'apuração própria. A quantidade vendida saiu da compra em '
        '${fmtMes(mes)}.\n\n$txtDarf';
  }

  (Lote, Venda) _acharVenda(Mes d, String vendaId) {
    for (final l in d.lotes) {
      for (final v in l.vendas) {
        if (v.id == vendaId) return (l, v);
      }
    }
    throw ErroValidacao('Venda não encontrada.');
  }

  Future<VisaoMes> editarVenda(String mes, String vendaId, NovaVenda v) async {
    final d = _mesEditavel(mes);
    final (lote, venda) = _acharVenda(d, vendaId);
    final r = _validarVenda(mes, semVenda(lote, vendaId), v, edicao: true);
    venda
      ..data = r.data
      ..qtd = r.qtd
      ..preco = r.preco;
    repo.salvar(d);
    _gravou();
    return _visaoDe(mes, d);
  }

  Future<VisaoMes> excluirVenda(String mes, String vendaId) async {
    final d = _mesEditavel(mes);
    _acharVenda(d, vendaId);
    final grupo = grupoDe(vendaId);
    for (final l in d.lotes) {
      l.vendas = [
        for (final x in l.vendas)
          if (grupoDe(x.id) != grupo) x,
      ];
    }
    repo.salvar(d);
    _gravou();
    return _visaoDe(mes, d);
  }

  // --- venda em várias compras (alocação por quantidade)

  Future<String> novoGrupoVenda() async => ambiente.novoId();

  Future<List<Lote>> comprasElegiveis(
    String mes,
    String ticker,
    String data,
  ) async => nc.comprasElegiveis(_lerMes(mes), ticker, data);

  Future<PreviaVenda> previaVenda(String mes, NovaVendaQtd v) async {
    final d = _lerMes(mes);
    final itens = alocarPedido(d, mes, v);
    return previa(d, itens, v.preco, v.data);
  }

  Future<VendaRegistrada> registrarVendaQtd(String mes, NovaVendaQtd v) async {
    _lerMes(mes);
    final r = confirmarVenda(repo, mes, v);
    if (r.duplicada) {
      return VendaRegistrada(
        visao: _visaoDe(mes, r.mes),
        aviso: 'Essa venda já foi registrada.',
      );
    }
    _gravou();
    return VendaRegistrada(visao: _visaoDe(mes, r.mes));
  }

  Future<VisaoMes> editarGrupoVenda(
    String mes,
    String grupo,
    NovaVendaQtd v,
  ) async {
    _lerMes(mes);
    final d = editarGrupo(repo, mes, grupo, v);
    _gravou();
    return _visaoDe(mes, d);
  }

  Future<Fechamento> fecharMes(String mes) async {
    final d = _mesEditavel(mes);
    // o núcleo grava o mês fechado antes de ler o seguinte: valida antes
    _lerMes(proximoMes(mes));
    final (r, prox) = nc.fecharMes(repo, d);
    _gravou();
    return Fechamento(
      visao: _visaoDe(mes, d),
      mensagem: mensagemFechamento(r, prox),
    );
  }

  // --- caixa

  VisaoCaixa _visaoCaixa(Config cfg, Map<String, Mes> meses, {String? amigo}) {
    final hoje = ambiente.hoje();
    final resumo = resumoCaixa(cfg, meses, hoje: hoje);
    return VisaoCaixa(
      resumo: resumo,
      projecao: projecaoCaixa(resumo, hoje: hoje),
      agenda: agendaCaixa(resumo, hoje: hoje),
      hoje: hoje,
      amigo: amigo,
    );
  }

  Future<VisaoCaixa> caixa({String? amigo}) async {
    if (amigo != null) {
      final dados = _dadosAmigo(amigo);
      return _visaoCaixa(
        Config(caixa: dados.caixa ?? Caixa()),
        dados.meses,
        amigo: amigo,
      );
    }
    return _visaoCaixa(lerConfigParaGravar(repo), _carregarTodos());
  }

  Future<VisaoCaixa> alterarSaldo(ModoSaldo modo, double valor) async {
    if (valor.isNaN || valor.isInfinite) {
      throw ErroValidacao('Informe um valor válido.');
    }
    if (modo != ModoSaldo.definir && !(valor > 0)) {
      throw ErroValidacao('Informe um valor maior que zero.');
    }
    final cfg = lerConfigParaGravar(repo);
    final meses = _carregarTodos();
    switch (modo) {
      case ModoSaldo.definir:
        definirSaldo(cfg, valor);
      case ModoSaldo.aporte:
        ajustarSaldo(cfg, meses, valor);
      case ModoSaldo.retirada:
        ajustarSaldo(cfg, meses, -valor);
    }
    repo.gravarConfig(cfg);
    _gravou();
    return _visaoCaixa(cfg, meses);
  }
}
