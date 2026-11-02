// Formulário de venda: nova e edição (calculadora_darf.py:314-535;
// android/main.py:1302-1548).

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
import 'painel_resumo_ordem.dart';

/// Nulo quando o usuário cancela ou o mês não aceita alterações. [lote] e
/// [ticker] são a escolha inicial; [editar] é a compra com a venda editada
/// (a compra fica fixa). Numa venda retroativa o aviso devolvido pelo serviço
/// aparece aqui, depois de gravar (py:1655-1670); quem chama não o repete.
Future<VendaRegistrada?> abrirFormVenda(
  BuildContext c,
  VisaoMes visao, {
  Lote? lote,
  String ticker = '',
  (Lote, Venda)? editar,
}) async {
  if (!visao.editavel) return null;
  if (editar == null && !visao.dados.lotes.any((l) => restante(l) > 0)) {
    await avisar(c, 'Registrar venda', 'Não há compras em aberto neste mês.');
    return null;
  }
  if (!c.mounted) return null;
  final r = await abrirFormulario<VendaRegistrada>(
    c,
    (dialogo) => FormVenda(
      visao: visao,
      lote: lote,
      ticker: ticker,
      editar: editar,
      dialogo: dialogo,
    ),
  );
  final aviso = r?.aviso;
  if (r != null && aviso != null && c.mounted) {
    await avisar(c, 'Venda registrada', aviso);
  }
  return r;
}

class FormVenda extends StatefulWidget {
  const FormVenda({
    super.key,
    required this.visao,
    required this.dialogo,
    this.lote,
    this.ticker = '',
    this.editar,
  });

  final VisaoMes visao;
  final bool dialogo;
  final Lote? lote;
  final String ticker;
  final (Lote, Venda)? editar;

  @override
  State<FormVenda> createState() => _FormVendaState();
}

class _FormVendaState extends State<FormVenda>
    with SalvarFormulario<FormVenda, VendaRegistrada> {
  final TextEditingController _ticker = TextEditingController();
  final TextEditingController _qtd = TextEditingController();
  final TextEditingController _preco = TextEditingController();
  final FocusNode _focoPreco = FocusNode();
  late final List<Lote> _abertos;
  late final String _inicioMes;
  late final String _fimMes;
  late final bool _editando;

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

  /// Último preço preenchido pela cotação e a busca em andamento.
  String _precoAuto = '';
  (String, String)? _pedido;
  String _infoPreco = '';

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    _editando = e != null;
    _abertos = e != null
        ? [semVenda(e.$1, e.$2.id)]
        : [
            for (final l in widget.visao.dados.lotes)
              if (restante(l) > 0) l,
          ];
    final (inicio, fim) = limitesMes(widget.visao.mes);
    _inicioMes = inicio;
    _fimMes = fim;
    final inicial = e != null ? _abertos.first : widget.lote;
    final t = inicial?.ticker ?? widget.ticker;
    if (t.isNotEmpty) _ticker.text = t;
    _selecionarTicker(t, loteInicial: inicial, aoIniciar: true);
    if (e != null) {
      _data = e.$2.data;
      _qtd.text = '${e.$2.qtd}';
      _preco.text = fmtNum(e.$2.preco);
    }
    if (!_editando) _carregar();
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
    _ticker.dispose();
    _qtd.dispose();
    _preco.dispose();
    _focoPreco.dispose();
    super.dispose();
  }

  /// Dias do mês aberto, ou de meses anteriores que aceitam venda retroativa
  /// (py:407-415). Antes de saber quais aceitam, só o mês aberto.
  bool _permitida(String iso) {
    if (iso.compareTo(_inicioMes) >= 0) return true;
    if (_editando || !_mesesCarregados) return false;
    return !_semRetroativa.contains(iso.substring(0, 7));
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
      _selecionarLote(alvo.$1, aoIniciar: aoIniciar);
    } else {
      _rotulo = null;
      _lote = null;
      _minimo = _maximo = null;
      if (!aoIniciar) setState(() {});
    }
  }

  void _selecionarLote(String rotulo, {bool aoIniciar = false}) {
    final l = _opcoes.firstWhere((o) => o.$1 == rotulo).$2;
    final hoje = ambiente.hoje();
    var minimo = l.dataCompra;
    if (_editando && _inicioMes.compareTo(minimo) > 0) minimo = _inicioMes;
    final maximo = _fimMes.compareTo(hoje) < 0 ? _fimMes : hoje;
    _rotulo = rotulo;
    _lote = l;
    _minimo = minimo;
    _maximo = maximo;
    _qtd.text = '${restante(l)}';
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
    _sugerirPreco();
    if (!aoIniciar) setState(() {});
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
    final l = _lote;
    final d = _data;
    final retroativa =
        !_editando && l != null && d != null && d.compareTo(_inicioMes) < 0;
    final reservado = retroativa ? await s.reservadoEmMetas(l.id) : 0;
    final v = validarVenda(
      lote: l,
      data: d,
      qtd: _qtd.text,
      preco: _preco.text,
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
  });

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final l = _lote;
    final suave = TextStyle(color: c.textoSuave, fontSize: 12);
    var info = '';
    if (l != null) {
      info =
          '${l.tipo}  ·  Custo ${brl(l.preco)}  ·  Disponível: ${restante(l)}';
      if ((_minimo ?? '').compareTo(_maximo ?? '') > 0) {
        info += '\nNão há data válida para vender essa compra neste mês.';
      }
    }
    final semOpcao = _tickerAtual == null || _tickerAtual!.isEmpty
        ? 'Escolha um ticker'
        : 'Nenhuma compra em aberto desse ticker';
    final r = _resumo();
    return QuadroFormulario(
      dialogo: widget.dialogo,
      titulo: _editando ? 'Editar venda' : 'Registrar venda',
      erro: erro,
      salvando: salvando,
      aoSalvar: _salvar,
      children: [
        Text('Mês ${fmtMes(widget.visao.mes)}', style: suave),
        TextField(
          key: const ValueKey('ticker'),
          controller: _ticker,
          enabled: !_editando,
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
                  if (rot != null) _selecionarLote(rot);
                },
        ),
        if (info.isNotEmpty) Text(info, style: suave),
        CampoData(
          // data recriada quando muda a compra (limites diferentes)
          key: ValueKey('data-${l?.id}'),
          valor: _data,
          minimo: _minimo,
          maximo: _maximo,
          permitido: _permitida,
          aoMudar: (d) {
            _data = d;
            _sugerirPreco();
            setState(() {});
          },
        ),
        TextField(
          key: const ValueKey('qtd'),
          controller: _qtd,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l == null
                ? 'Quantidade'
                : 'Quantidade (máx. ${restante(l)})',
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const ValueKey('preco'),
          controller: _preco,
          focusNode: _focoPreco,
          autofocus: !_editando && _ticker.text.isNotEmpty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Preço unitário (R\$)',
            hintText: 'Ex.: 35,10',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_infoPreco.isNotEmpty)
          Text(_infoPreco, style: TextStyle(color: c.textoSuave, fontSize: 11)),
        PainelResumoOrdem(
          resumo: r,
          nota: r == null ? '' : notaResumoVenda(_data == l?.dataCompra),
        ),
      ],
    );
  }
}
