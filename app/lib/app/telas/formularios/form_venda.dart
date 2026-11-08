// Formulário de venda: nova e edição (calculadora_darf.py:314-535;
// android/main.py:1302-1548). A venda do mês aberto é por quantidade, em modo
// automático ou manual, e pode usar várias compras; a retroativa e a edição de
// uma linha só seguem com uma compra.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/campo_data.dart';
import '../../componentes/chips_ticker.dart';
import '../../componentes/dialogos.dart';
import '../../regras/formularios.dart';
import '../../regras/textos.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'abrir_formulario.dart';
import 'painel_previa_venda.dart';
import 'painel_resumo_ordem.dart';

/// Como as compras da venda são escolhidas.
enum ModoVenda { automatico, manual }

/// Espera após a última tecla antes de recalcular a prévia.
const _esperaPrevia = Duration(milliseconds: 300);

/// Nulo quando o usuário cancela ou o mês não aceita alterações. [lote] e
/// [ticker] são a escolha inicial; [editar] é a compra com a venda editada
/// (a compra fica fixa). Numa venda retroativa o aviso devolvido pelo serviço
/// aparece aqui, depois de gravar (py:1655-1670); quem chama não o repete.
/// [fecharMesAberto] fecha o mês da visão do formulário pelo fluxo do "Fechar mês" da
/// Apuração e devolve a visão do novo mês aberto (nula se cancelou ou
/// falhou); sem ela, o formulário só avisa que o mês precisa ser fechado.
Future<VendaRegistrada?> abrirFormVenda(
  BuildContext c,
  VisaoMes visao, {
  Lote? lote,
  String ticker = '',
  (Lote, Venda)? editar,
  FecharMesAberto? fecharMesAberto,
}) async {
  if (!visao.editavel) return null;
  if (editar == null && !visao.dados.lotes.any((l) => restante(l) > 0)) {
    await avisar(c, 'Registrar venda', 'Não há compras em aberto neste mês.');
    return null;
  }
  if (!c.mounted) return null;
  final r = await abrirFormulario<VendaRegistrada>(
    c,
    (dialogo) => _TrocaDeMes(
      visao: visao,
      construir: (v, trocou, aoTrocar) => FormVenda(
        // um mês novo recria o formulário: os lotes e limites são outros
        key: ValueKey('venda-${v.mes}'),
        visao: v,
        lote: trocou == null ? lote : null,
        ticker: trocou ?? ticker,
        editar: editar,
        dialogo: dialogo,
        fecharMesAberto: fecharMesAberto == null
            ? null
            : (fc, t) async {
                final nova = await fecharMesAberto(fc, v);
                if (nova != null) aoTrocar(nova, t);
              },
      ),
    ),
  );
  final aviso = r?.aviso;
  if (r != null && aviso != null && c.mounted) {
    await avisar(c, 'Venda registrada', aviso);
  }
  return r;
}

/// Fecha o mês aberto a partir do formulário; devolve a visão do novo mês
/// aberto, ou nulo se o fechamento foi cancelado ou falhou.
typedef FecharMesAberto = Future<VisaoMes?> Function(
  BuildContext c,
  VisaoMes aberta,
);

/// Guarda a visão do formulário: depois de fechar o mês pelo botão, o
/// formulário é refeito com o novo mês aberto, mantendo o ticker digitado.
class _TrocaDeMes extends StatefulWidget {
  const _TrocaDeMes({required this.visao, required this.construir});

  final VisaoMes visao;
  final Widget Function(
    VisaoMes visao,
    String? tickerAposTroca,
    void Function(VisaoMes nova, String ticker) aoTrocar,
  )
  construir;

  @override
  State<_TrocaDeMes> createState() => _TrocaDeMesState();
}

class _TrocaDeMesState extends State<_TrocaDeMes> {
  late VisaoMes _visao = widget.visao;
  String? _ticker;

  void _trocar(VisaoMes nova, String ticker) {
    if (!mounted) return;
    setState(() {
      _visao = nova;
      _ticker = ticker;
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.construir(_visao, _ticker, _trocar);
}

class FormVenda extends StatefulWidget {
  const FormVenda({
    super.key,
    required this.visao,
    required this.dialogo,
    this.lote,
    this.ticker = '',
    this.editar,
    this.fecharMesAberto,
  });

  final VisaoMes visao;
  final bool dialogo;
  final Lote? lote;
  final String ticker;
  final (Lote, Venda)? editar;

  /// Fecha o mês da [visao] (botão do aviso de mês terminado); recebe o
  /// ticker digitado para o formulário do novo mês.
  final Future<void> Function(BuildContext c, String ticker)? fecharMesAberto;

  @override
  State<FormVenda> createState() => _FormVendaState();
}

class _FormVendaState extends State<FormVenda>
    with SalvarFormulario<FormVenda, VendaRegistrada> {
  final TextEditingController _ticker = TextEditingController();
  final TextEditingController _qtd = TextEditingController();
  final TextEditingController _preco = TextEditingController();
  final FocusNode _focoPreco = FocusNode();
  final Map<String, TextEditingController> _ctrlsSel = {};
  late final List<Lote> _abertos;
  late final Mes _dados;
  late final String _inicioMes;
  late final String _fimMes;
  late final bool _editando;

  /// Id do grupo editado (venda em várias compras) ou nulo.
  late final String? _grupoEdicao;

  /// Id da venda nova, pedido quando o formulário abre: é a chave que torna a
  /// confirmação repetida inofensiva.
  Future<String>? _grupoNovo;

  List<String> _sugestoes = const [];
  Set<String> _semRetroativa = const {};
  bool _mesesCarregados = false;
  String? _tickerAtual;
  List<(String, Lote)> _opcoes = const [];
  String? _rotulo;
  Lote? _lote;
  String? _data;
  String? _minimo;
  String? _maximo;

  ModoVenda _modo = ModoVenda.automatico;

  /// Quantidade escolhida por compra no modo manual.
  Map<String, int> _sel = {};

  PreviaVenda? _previa;
  String _erroPrevia = '';
  int _seqPrevia = 0;
  Timer? _timerPrevia;

  /// Último preço preenchido pela cotação e a busca em andamento.
  String _precoAuto = '';
  (String, String)? _pedido;
  String _infoPreco = '';

  bool get _editandoGrupo => _grupoEdicao != null;

  /// Venda de mês anterior: uma compra só, como na versão anterior.
  bool get _retro =>
      !_editando && _data != null && _data!.compareTo(_inicioMes) < 0;

  /// Fluxo de uma compra só: venda retroativa e edição de uma linha.
  bool get _legado => _retro || (_editando && !_editandoGrupo);

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    _editando = e != null;
    final grupo = e == null ? null : grupoDe(e.$2.id);
    final linhas = [
      if (grupo != null)
        for (final l in widget.visao.dados.lotes)
          for (final v in l.vendas)
            if (grupoDe(v.id) == grupo) (l, v),
    ];
    _grupoEdicao = linhas.length > 1 ? grupo : null;
    if (_editandoGrupo) {
      // as vendas do grupo saem: a quantidade delas volta a ficar disponível
      _dados = semGrupo(widget.visao.dados, grupo!);
    } else {
      _dados = widget.visao.dados;
    }
    _abertos = e != null && !_editandoGrupo
        ? [semVenda(e.$1, e.$2.id)]
        : [
            for (final l in _dados.lotes)
              if (restante(l) > 0) l,
          ];
    final (inicio, fim) = limitesMes(widget.visao.mes);
    _inicioMes = inicio;
    _fimMes = fim;
    final inicial = e != null && !_editandoGrupo
        ? _abertos.first
        : (e != null ? e.$1 : widget.lote);
    final t = inicial?.ticker ?? widget.ticker;
    if (t.isNotEmpty) _ticker.text = t;
    if (!_editando && widget.lote != null) _modo = ModoVenda.manual;
    _selecionarTicker(t, loteInicial: inicial, aoIniciar: true);
    if (e != null) {
      _data = e.$2.data;
      _preco.text = fmtNum(e.$2.preco);
      if (_editandoGrupo) {
        _qtd.text = '${linhas.fold(0, (soma, x) => soma + x.$2.qtd)}';
        _modo = ModoVenda.manual;
        _aplicarSel({for (final (l, v) in linhas) l.id: v.qtd});
      } else {
        _qtd.text = '${e.$2.qtd}';
      }
    }
    if (!_editando) {
      _carregar();
      _grupoNovo = context.read<ServicosApp>().novoGrupoVenda()..ignore();
    }
    _agendarPrevia();
  }

  /// Atalhos "Em carteira" e meses que recusam venda retroativa.
  void _carregar() {
    final s = context.read<ServicosApp>();
    final mes = widget.visao.mes;
    s
        .sugestoesTicker(mes, soCustodia: true)
        .then(
          (r) {
            if (mounted) setState(() => _sugestoes = r.tickers);
          },
          onError: (Object _) {
            // sem atalhos: o ticker continua digitável
          },
        );
    s
        .mesesSemVendaRetroativa(mes)
        .then(
          (r) {
            if (!mounted) return;
            setState(() {
              _semRetroativa = r;
              _mesesCarregados = true;
            });
          },
          onError: (Object e) {
            if (mounted) setState(() => erro = textoErro(e));
          },
        );
  }

  @override
  void dispose() {
    _timerPrevia?.cancel();
    _ticker.dispose();
    _qtd.dispose();
    _preco.dispose();
    _focoPreco.dispose();
    for (final c in _ctrlsSel.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Dias do mês aberto, ou de meses anteriores que aceitam venda retroativa
  /// (py:407-415). Antes de saber quais aceitam, só o mês aberto.
  bool _permitida(String iso) {
    if (iso.compareTo(_inicioMes) >= 0) return true;
    if (_editando || !_mesesCarregados) return false;
    return !_semRetroativa.contains(iso.substring(0, 7));
  }

  // --- compras elegíveis e seleção manual

  /// Compras do ticker que existiam na data da venda e ainda têm saldo, da
  /// mais antiga para a mais nova.
  List<Lote> get _elegiveis {
    final d = _data;
    final t = _tickerAtual;
    if (d == null || t == null || t.isEmpty) return const [];
    return ordenadoPor(
      comprasElegiveis(_dados, t, d),
      (l) => [l.dataCompra, l.id],
    );
  }

  int? get _qtdValida {
    try {
      return parseQtd(_qtd.text);
    } on FormatException {
      return null;
    }
  }

  /// Muda quando o conjunto de compras (ou o que é do dia) muda.
  String _assinatura() =>
      [for (final l in _elegiveis) '${l.id}:${l.dataCompra == _data}']
          .join('|');

  /// Compras do dia: parte de day trade obrigatória, preenchida sozinha.
  Map<String, int> _travadas(List<Lote> el, int qtd) {
    final dia = [
      for (final l in el)
        if (l.dataCompra == _data) l,
    ];
    final disp = dia.fold(0, (soma, l) => soma + restante(l));
    final forcado = disp < qtd ? disp : qtd;
    if (forcado <= 0) return {};
    return {
      for (final i in alocarAutomatico(dia, forcado, _data!)) i.lote.id: i.qtd,
    };
  }

  /// Ponto de partida do modo manual: a alocação automática, ou, ao abrir por
  /// uma compra, essa compra com o que falta além do day trade.
  void _reiniciarSelecao({Lote? inicial}) {
    final el = _elegiveis;
    final q = _qtdValida;
    final m = <String, int>{};
    if (q != null && el.isNotEmpty && _data != null) {
      try {
        if (inicial == null) {
          for (final i in alocarAutomatico(el, q, _data!)) {
            m[i.lote.id] = i.qtd;
          }
        } else {
          m.addAll(_travadas(el, q));
          final resto = q - m.values.fold(0, (soma, n) => soma + n);
          if (!m.containsKey(inicial.id) &&
              el.any((l) => l.id == inicial.id) &&
              resto > 0) {
            final max = restante(inicial);
            m[inicial.id] = (resto < max ? resto : max).toInt();
          }
        }
      } on ErroValidacao {
        // quantidade acima do disponível: começa vazio e o aviso explica
        m.clear();
      }
    }
    _aplicarSel(m);
  }

  /// Quantidade total mudou: as compras do dia seguem a parte obrigatória.
  void _atualizarTravadas() {
    final el = _elegiveis;
    final q = _qtdValida;
    final m = {..._sel};
    for (final l in el) {
      if (l.dataCompra == _data) m.remove(l.id);
    }
    if (q != null && _data != null) {
      try {
        m.addAll(_travadas(el, q));
      } on ErroValidacao {
        // sem compras do dia consumíveis
      }
    }
    _aplicarSel(m);
  }

  void _aplicarSel(Map<String, int> m) {
    _sel = m;
    for (final e in _ctrlsSel.entries) {
      final n = m[e.key] ?? 0;
      e.value.text = n > 0 ? '$n' : '';
    }
  }

  TextEditingController _ctrlSel(String id) => _ctrlsSel.putIfAbsent(id, () {
    final n = _sel[id] ?? 0;
    return TextEditingController(text: n > 0 ? '$n' : '');
  });

  List<ItemAlocacao> _itensSel(List<Lote> el) => [
    for (final l in el)
      if ((_sel[l.id] ?? 0) > 0) ItemAlocacao(l, _sel[l.id]!),
  ];

  /// Mensagem da seleção manual; nulo quando a soma e os limites valem.
  String? _erroManual(List<Lote> el) {
    final q = _qtdValida;
    if (q == null) return null;
    return validarManual(el, _itensSel(el), q, _data ?? '');
  }

  bool get _podeSalvar {
    if (_legado || _modo == ModoVenda.automatico) return true;
    final q = _qtdValida;
    if (q == null) return false;
    return _erroManual(_elegiveis) == null;
  }

  // --- mês aberto já terminado

  /// Com ticker, a data vai até o fim do mês aberto; se hoje já passou dele,
  /// vender no mês de hoje pede fechar o mês aberto (sem ticker, nada muda).
  bool get _mesAbertoTerminou =>
      !_editando && _maximo != null && _fimMes.compareTo(ambiente.hoje()) < 0;

  bool _fechandoMes = false;

  Future<void> _fecharMesAberto() async {
    final fechar = widget.fecharMesAberto;
    if (fechar == null || _fechandoMes) return;
    setState(() => _fechandoMes = true);
    try {
      await fechar(context, _ticker.text.trim().toUpperCase());
    } finally {
      if (mounted) setState(() => _fechandoMes = false);
    }
  }

  Widget _avisoMesTerminado(CoresApp c) {
    final aberto = widget.visao.mes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          textoVenderDepoisDoMesAberto(ambiente.hoje(), aberto),
          key: const ValueKey('aviso-mes-terminado'),
          style: TextStyle(color: c.aviso, fontWeight: FontWeight.w600),
        ),
        if (widget.fecharMesAberto != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: salvando || _fechandoMes ? null : _fecharMesAberto,
              child: Text(rotuloFecharMesAberto(aberto)),
            ),
          ),
      ],
    );
  }

  // --- ticker e compra

  void _selecionarTicker(
    String texto, {
    Lote? loteInicial,
    bool aoIniciar = false,
  }) {
    final t = texto.trim().toUpperCase();
    if (t == _tickerAtual && loteInicial == null) return;
    _tickerAtual = t;
    final opcoes = <(String, Lote)>[];
    for (final l in _abertos.where((l) => l.ticker == t)) {
      final base =
          '${fmtData(l.dataCompra)}  ·  ${brl(l.preco)}  ·  ${restante(l)} disp.';
      var rot = base;
      var n = 2;
      while (opcoes.any((o) => o.$1 == rot)) {
        rot = '$base (${n++})';
      }
      opcoes.add((rot, l));
    }
    _opcoes = opcoes;
    if (opcoes.isNotEmpty) {
      final alvo = opcoes.firstWhere(
        (o) => loteInicial != null && o.$2.id == loteInicial.id,
        orElse: () => opcoes.first,
      );
      _definirLote(alvo.$1);
      _ajustarData();
      _qtd.text = '${_qtdPadrao(loteInicial)}';
      _reiniciarSelecao(inicial: loteInicial);
      _sugerirPreco();
    } else {
      _rotulo = null;
      _lote = null;
      _minimo = _maximo = null;
      _reiniciarSelecao();
    }
    _agendarPrevia();
    if (!aoIniciar) setState(() {});
  }

  /// Compra do dropdown (fluxo de uma compra só) e os limites da data: da
  /// compra mais antiga do ticker até hoje ou o fim do mês.
  void _definirLote(String rotulo) {
    final l = _opcoes.firstWhere((o) => o.$1 == rotulo).$2;
    var minimo = _opcoes
        .map((o) => o.$2.dataCompra)
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    if (_editando && _inicioMes.compareTo(minimo) > 0) minimo = _inicioMes;
    _rotulo = rotulo;
    _lote = l;
    _minimo = minimo;
    _maximo = _fimMes.compareTo(ambiente.hoje()) < 0
        ? _fimMes
        : ambiente.hoje();
  }

  /// Mantém a data se couber nos limites; senão hoje, se couber.
  void _ajustarData() {
    final hoje = ambiente.hoje();
    final minimo = _minimo!;
    final maximo = _maximo!;
    var d = _data;
    if (d != null && (d.compareTo(minimo) < 0 || d.compareTo(maximo) > 0)) {
      d = null;
    }
    if (d == null &&
        minimo.compareTo(hoje) <= 0 &&
        hoje.compareTo(maximo) <= 0) {
      d = hoje;
    }
    _data = d;
  }

  /// Quantidade inicial: a da compra aberta pelo usuário ou o fluxo de uma
  /// compra só; senão tudo o que há disponível do ticker na data.
  int _qtdPadrao(Lote? inicial) {
    if (inicial != null && _opcoes.any((o) => o.$2.id == inicial.id)) {
      return restante(inicial);
    }
    if (_legado) return restante(_lote!);
    final el = _elegiveis;
    final base = el.isNotEmpty ? el : [for (final o in _opcoes) o.$2];
    return base.fold(0, (soma, l) => soma + restante(l));
  }

  void _escolherCompra(String rotulo) {
    _definirLote(rotulo);
    _qtd.text = '${restante(_lote!)}';
    _sugerirPreco();
    setState(() {});
  }

  void _mudouData(String? d) {
    final eraLegado = _legado;
    final antes = _assinatura();
    _data = d;
    if (_legado != eraLegado && _lote != null && !_editando) {
      _qtd.text = '${_qtdPadrao(null)}';
    }
    if (_assinatura() != antes || _legado != eraLegado) _reiniciarSelecao();
    _sugerirPreco();
    _agendarPrevia();
    setState(() {});
  }

  void _mudouModo(ModoVenda m) {
    if (m == _modo) return;
    // só muda o formulário: nada é gravado
    if (m == ModoVenda.manual) _reiniciarSelecao();
    setState(() => _modo = m);
    _agendarPrevia();
  }

  void _mudouQtd() {
    if (_modo == ModoVenda.manual) _atualizarTravadas();
    _agendarPrevia();
    setState(() {});
  }

  // --- preço sugerido

  /// Verdadeiro se o usuário digitou um preço diferente do sugerido.
  bool get _precoManual {
    final p = _preco.text.trim();
    return p.isNotEmpty && p != _precoAuto;
  }

  /// Cotação atual (venda hoje) ou fechamento da data escolhida; nunca
  /// sobrescreve o que o usuário digitou (py:462-503).
  void _sugerirPreco() {
    final l = _lote;
    final d = _data;
    if (_editando || l == null || d == null || _precoManual) return;
    final pedido = (l.ticker, d);
    if (pedido == _pedido) return;
    _pedido = pedido;
    _infoPreco = 'Buscando cotação…';
    context
        .read<ServicosApp>()
        .precoVenda(pedido.$1, pedido.$2)
        .then(
          (r) {
            // pedido mais novo, ou preço digitado nesse meio-tempo
            if (!mounted || _pedido != pedido || _precoManual) return;
            setState(() {
              _precoAuto = precoTexto(r.$1);
              _preco.text = _precoAuto;
              _infoPreco = '${r.$2} · pode alterar';
            });
            _agendarPrevia();
          },
          onError: (Object e) {
            if (!mounted || _pedido != pedido || _precoManual) return;
            if (e is PedidoSuperado) return;
            setState(() {
              _pedido = null;
              _infoPreco =
                  'Não foi possível buscar a cotação. Informe o preço.';
            });
          },
        );
  }

  // --- prévia (fiscal x gerencial)

  /// Pedido válido para a prévia ou nulo (campos incompletos). A confirmação
  /// usa o mesmo pedido, com o id da venda.
  Validacao<NovaVendaQtd> _pedidoVenda(String grupo) {
    final d = _data;
    return validarVendaQtd(
      ticker: _ticker.text,
      data: d,
      qtd: _qtd.text,
      preco: _preco.text,
      inicioMes: _inicioMes,
      permitida: d != null && _permitida(d),
      elegiveis: _elegiveis,
      grupo: grupo,
      selecao: _modo == ModoVenda.manual ? _sel : null,
    );
  }

  void _agendarPrevia() {
    _timerPrevia?.cancel();
    _seqPrevia++;
    if (_legado) {
      _previa = null;
      _erroPrevia = '';
      return;
    }
    _timerPrevia = Timer(_esperaPrevia, _calcularPrevia);
  }

  Future<void> _calcularPrevia() async {
    // ao editar, o grupo é o próprio: o serviço libera a quantidade dele
    final v = _pedidoVenda(_grupoEdicao ?? 'previa');
    if (v is! Valido<NovaVendaQtd>) {
      if (_previa != null || _erroPrevia.isNotEmpty) {
        setState(() {
          _previa = null;
          _erroPrevia = '';
        });
      }
      return;
    }
    final seq = ++_seqPrevia;
    try {
      final r = await context.read<ServicosApp>().previaVenda(
        widget.visao.mes,
        v.valor,
      );
      if (!mounted || seq != _seqPrevia) return;
      setState(() {
        _previa = r;
        _erroPrevia = '';
      });
    } catch (e) {
      if (!mounted || seq != _seqPrevia || e is PedidoSuperado) return;
      setState(() {
        _previa = null;
        _erroPrevia = textoErro(e);
      });
    }
  }

  // --- resumo e salvar

  ResumoOrdem? _resumo() {
    final l = _lote;
    final d = _data;
    if (l == null || d == null) return null;
    try {
      return resumoOrdem(
        'venda',
        parseQtd(_qtd.text),
        parseNum(_preco.text),
        d,
        precoCompra: l.preco,
        dayTrade: d == l.dataCompra,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _salvar() => salvarCom(() async {
    final s = context.read<ServicosApp>();
    if (_legado) return _salvarUmaCompra(s);
    final mes = widget.visao.mes;
    // tudo é lido antes do await: o que foi validado é o que vai ao serviço
    final novo = _grupoNovo;
    final grupo = _grupoEdicao ?? await novo!;
    final v = _pedidoVenda(grupo);
    switch (v) {
      case Invalido(:final mensagem):
        erro = mensagem;
        return null;
      case Valido(:final valor):
        final g = _grupoEdicao;
        if (g != null) {
          return VendaRegistrada(
            visao: await s.editarGrupoVenda(mes, g, valor),
          );
        }
        return s.registrarVendaQtd(mes, valor);
    }
  });

  Future<VendaRegistrada?> _salvarUmaCompra(ServicosApp s) async {
    final l = _lote;
    final d = _data;
    // lidos antes do await: o que foi validado é o que vai ao serviço
    final qtd = _qtd.text;
    final preco = _preco.text;
    final retroativa =
        !_editando && l != null && d != null && d.compareTo(_inicioMes) < 0;
    final reservado = retroativa ? await s.reservadoEmMetas(l.id) : 0;
    final v = validarVenda(
      lote: l,
      data: d,
      qtd: qtd,
      preco: preco,
      inicioMes: _inicioMes,
      permitida: d != null && _permitida(d),
      reservado: reservado,
      editando: _editando,
    );
    switch (v) {
      case Invalido(:final mensagem):
        erro = mensagem;
        return null;
      case Valido(:final valor):
        final e = widget.editar;
        final mes = widget.visao.mes;
        if (e == null) return s.registrarVenda(mes, valor);
        return VendaRegistrada(visao: await s.editarVenda(mes, e.$2.id, valor));
    }
  }

  // --- tela

  Widget _modos() => SegmentedButton<ModoVenda>(
    key: const ValueKey('modo-venda'),
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: ModoVenda.automatico, label: Text('Automático')),
      ButtonSegment(value: ModoVenda.manual, label: Text('Manual')),
    ],
    selected: {_modo},
    onSelectionChanged: salvando ? null : (s) => _mudouModo(s.first),
  );

  /// Automático com quantidade acima do disponível: a mensagem do núcleo.
  String _erroAutomatico() {
    final q = _qtdValida;
    final el = _elegiveis;
    if (_modo != ModoVenda.automatico || q == null || el.isEmpty) return '';
    try {
      alocarAutomatico(el, q, _data!);
    } on ErroValidacao catch (e) {
      return e.mensagem;
    }
    return '';
  }

  /// Resumo financeiro da ordem somado por compra da prévia.
  Widget _resumoNovo() {
    final p = _previa;
    ResumoOrdem? r;
    var nota = '';
    if (p != null && _data != null) {
      try {
        r = resumoVendaPrevia(p, parseNum(_preco.text), _data!);
      } on FormatException {
        r = null;
      }
      if (r != null && p.qtdDt > 0 && p.qtdComum == 0) {
        nota = notaResumoVenda(true);
      } else if (r != null && p.qtdDt == 0) {
        nota = notaResumoVenda(false);
      }
    }
    return PainelResumoOrdem(resumo: r, nota: nota);
  }

  /// Compras escolhidas pelo serviço, com custo e resultado gerencial.
  Widget _linhasAutomatico(CoresApp c) {
    final p = _previa;
    final suave = TextStyle(color: c.textoSuave, fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(textoRegraAutomatico, style: suave),
        if (p != null)
          for (final l in p.linhas)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(
                    '${fmtData(l.item.lote.dataCompra)}  ·  ${l.item.qtd} ações'
                    '  ·  custo ${brl(l.custoEfetivo).replaceAll('R\$ ', 'R\$ ')}'
                    '${l.item.travado ? '  ·  day trade' : ''}',
                    style: TextStyle(color: c.texto, fontSize: 12),
                  ),
                ),
                Text(
                  'resultado ${brl(l.resultadoGerencial).replaceAll('R\$ ', 'R\$ ')}',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: c.texto, fontSize: 12),
                ),
              ],
            ),
      ],
    );
  }

  /// Só dígitos e no máximo [max] (o disponível da compra): reescreve o campo
  /// quando o texto passa do limite.
  int _limitar(String id, String texto, int max) {
    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    var n = digitos.isEmpty
        ? 0
        : (digitos.length > 9 ? max : int.parse(digitos));
    if (n > max) n = max;
    final novo = digitos.isEmpty ? '' : '$n';
    if (novo != texto) {
      _ctrlSel(id).value = TextEditingValue(
        text: novo,
        selection: TextSelection.collapsed(offset: novo.length),
      );
    }
    return n;
  }

  Widget _listaManual(CoresApp c) {
    final el = _elegiveis;
    final suave = TextStyle(color: c.textoSuave, fontSize: 12);
    final q = _qtdValida;
    final soma = _sel.values.fold(0, (a, b) => a + b);
    final msg = _erroManual(el);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (q != null)
          Text(
            textoSelecionado(soma, q),
            style: TextStyle(
              color: soma == q ? c.alta : c.texto,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (msg != null)
          Semantics(
            liveRegion: true,
            child: Text(msg, style: TextStyle(color: c.queda, fontSize: 12)),
          ),
        for (final l in el)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${fmtData(l.dataCompra)}  ·  original ${l.qtd}  ·  '
                      'disp. ${restante(l)}  ·  custo '
                      '${brl(custoUnitarioEfetivo(l))}',
                      style: TextStyle(color: c.texto, fontSize: 12),
                    ),
                    if (l.dataCompra == _data)
                      Text('Compra de hoje (day trade)', style: suave),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                child: TextField(
                  key: ValueKey('sel-${l.id}'),
                  controller: _ctrlSel(l.id),
                  enabled: l.dataCompra != _data,
                  readOnly: salvando,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    isDense: true,
                  ),
                  onChanged: (t) {
                    final n = _limitar(l.id, t, restante(l));
                    _sel = {..._sel}..remove(l.id);
                    if (n > 0) _sel[l.id] = n;
                    _agendarPrevia();
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final l = _lote;
    final suave = TextStyle(color: c.textoSuave, fontSize: 12);
    final legado = _legado;
    var info = '';
    if (legado && l != null) {
      info =
          '${l.tipo}  ·  Custo ${brl(l.preco)}  ·  Disponível: ${restante(l)}';
      if ((_minimo ?? '').compareTo(_maximo ?? '') > 0) {
        info += '\nNão há data válida para vender essa compra neste mês.';
      }
    }
    final semOpcao = _tickerAtual == null || _tickerAtual!.isEmpty
        ? 'Escolha um ticker'
        : 'Nenhuma compra em aberto desse ticker';
    final r = legado ? _resumo() : null;
    final disp = legado
        ? (l == null ? null : restante(l))
        : (_elegiveis.isEmpty
              ? null
              : _elegiveis.fold(0, (soma, x) => soma + restante(x)));
    return QuadroFormulario(
      dialogo: widget.dialogo,
      titulo: _editando ? 'Editar venda' : 'Registrar venda',
      erro: erro,
      salvando: salvando,
      aoSalvar: _salvar,
      podeSalvar: _podeSalvar,
      indicador: true,
      children: [
        Text('Mês ${fmtMes(widget.visao.mes)}', style: suave),
        TextField(
          key: const ValueKey('ticker'),
          controller: _ticker,
          enabled: !_editando,
          readOnly: salvando,
          autofocus: !_editando && _ticker.text.isEmpty,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Ticker',
            hintText: 'Ex.: PETR4',
          ),
          onChanged: (t) => _selecionarTicker(t),
        ),
        ChipsTicker(
          titulo: 'Em carteira',
          tickers: _sugestoes,
          marcado: _tickerAtual,
          aoEscolher: (t) {
            _ticker.text = t;
            _selecionarTicker(t);
          },
        ),
        if (legado)
          DropdownButtonFormField<String>(
            // novo valor inicial quando a lista de opções muda
            key: ValueKey('compra-${_tickerAtual ?? ''}-$_rotulo'),
            initialValue: _rotulo,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Compra'),
            disabledHint: Text(semOpcao),
            items: [
              for (final (rot, _) in _opcoes)
                DropdownMenuItem(value: rot, child: Text(rot)),
            ],
            onChanged: _editando || _opcoes.isEmpty
                ? null
                : (rot) {
                    if (rot != null) _escolherCompra(rot);
                  },
          )
        else if (_opcoes.isEmpty)
          Text(semOpcao, style: suave),
        if (info.isNotEmpty) Text(info, style: suave),
        if (_mesAbertoTerminou) _avisoMesTerminado(c),
        CampoData(
          // recriada quando muda o ticker (limites diferentes)
          key: ValueKey('data-${_tickerAtual ?? ''}'),
          valor: _data,
          minimo: _minimo,
          maximo: _maximo,
          permitido: _permitida,
          aoMudar: _mudouData,
        ),
        TextField(
          key: const ValueKey('qtd'),
          controller: _qtd,
          readOnly: salvando,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: disp == null ? 'Quantidade' : 'Quantidade (máx. $disp)',
          ),
          onChanged: (_) => _mudouQtd(),
        ),
        TextField(
          key: const ValueKey('preco'),
          controller: _preco,
          focusNode: _focoPreco,
          readOnly: salvando,
          autofocus: !_editando && _ticker.text.isNotEmpty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Preço unitário (R\$)',
            hintText: 'Ex.: 35,10',
          ),
          onChanged: (_) {
            _agendarPrevia();
            setState(() {});
          },
        ),
        if (_infoPreco.isNotEmpty)
          Text(_infoPreco, style: TextStyle(color: c.textoSuave, fontSize: 11)),
        if (legado)
          PainelResumoOrdem(
            resumo: r,
            nota: r == null ? '' : notaResumoVenda(_data == l?.dataCompra),
          )
        else if (_opcoes.isNotEmpty) ...[
          _modos(),
          if (_modo == ModoVenda.automatico)
            _linhasAutomatico(c)
          else
            _listaManual(c),
          PainelPreviaVenda(
            previa: _previa,
            erro: _erroPrevia.isNotEmpty ? _erroPrevia : _erroAutomatico(),
            // método do mês que calculou o fiscal; sem prévia, o do mês aberto
            custoMedio:
                _previa?.custoMedio ?? _dados.metodo == metodoCustoMedio,
          ),
          _resumoNovo(),
        ],
      ],
    );
  }
}
