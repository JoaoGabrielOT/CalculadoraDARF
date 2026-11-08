// Formulário de compra: novo ativo e edição (calculadora_darf.py:228-311;
// android/main.py:1185-1300).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/campo_data.dart';
import '../../componentes/chips_ticker.dart';
import '../../regras/formularios.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'abrir_formulario.dart';
import 'painel_resumo_ordem.dart';

/// Nulo quando o usuário cancela ou o mês não aceita alterações. [iniciais]
/// traz `ticker`, `qtd` e `preco` para preencher; [editar] é a compra editada.
Future<VisaoMes?> abrirFormCompra(
  BuildContext c,
  VisaoMes visao, {
  Map<String, String>? iniciais,
  Lote? editar,
}) {
  if (!visao.editavel) return Future.value(null);
  return abrirFormulario<VisaoMes>(
    c,
    (dialogo) => FormCompra(
      visao: visao,
      iniciais: iniciais,
      editar: editar,
      dialogo: dialogo,
    ),
  );
}

class FormCompra extends StatefulWidget {
  const FormCompra({
    super.key,
    required this.visao,
    required this.dialogo,
    this.iniciais,
    this.editar,
  });

  final VisaoMes visao;
  final bool dialogo;
  final Map<String, String>? iniciais;
  final Lote? editar;

  @override
  State<FormCompra> createState() => _FormCompraState();
}

class _FormCompraState extends State<FormCompra>
    with SalvarFormulario<FormCompra, VisaoMes> {
  late final Map<String, String> _ini;
  late final TextEditingController _ticker;
  late final TextEditingController _qtd;
  late final TextEditingController _preco;
  final FocusNode _focoQtd = FocusNode();
  late final String _maximo;
  String? _data;
  List<String> _frequentes = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.editar;
    _ini = e != null
        ? {'ticker': e.ticker, 'qtd': '${e.qtd}', 'preco': fmtNum(e.preco)}
        : widget.iniciais ?? const {};
    _ticker = TextEditingController(text: _ini['ticker'] ?? '');
    _qtd = TextEditingController(text: _ini['qtd'] ?? '');
    _preco = TextEditingController(text: _ini['preco'] ?? '');
    final hoje = ambiente.hoje();
    _data = e?.dataCompra ?? hoje;
    // Com vendas, a compra não pode ser depois da primeira (py:244).
    var maximo = hoje;
    for (final v in e?.vendas ?? const <Venda>[]) {
      if (v.data.compareTo(maximo) < 0) maximo = v.data;
    }
    _maximo = maximo;
    context
        .read<ServicosApp>()
        .sugestoesTicker(widget.visao.mes)
        .then(
          (s) {
            if (mounted) setState(() => _frequentes = s.tickers);
          },
          onError: (Object _) {
            // sem atalhos: o ticker continua digitável
          },
        );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _qtd.dispose();
    _preco.dispose();
    _focoQtd.dispose();
    super.dispose();
  }

  String get _tickerAtual => _ticker.text.trim().toUpperCase();

  void _escolher(String t) {
    setState(() => _ticker.text = t);
    _focoQtd.requestFocus();
  }

  ResumoOrdem? _resumo() {
    final d = _data;
    if (d == null) return null;
    try {
      return resumoOrdem(
        'compra',
        parseQtd(_qtd.text),
        parseNum(_preco.text),
        d,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _salvar() => salvarCom(() async {
    final v = validarCompra(
      ticker: _ticker.text,
      data: _data,
      qtd: _qtd.text,
      preco: _preco.text,
      hoje: ambiente.hoje(),
      editando: widget.editar,
      mes: widget.visao.dados,
    );
    switch (v) {
      case Invalido(:final mensagem):
        erro = mensagem;
        return null;
      case Valido(:final valor):
        final s = context.read<ServicosApp>();
        final e = widget.editar;
        final mes = widget.visao.mes;
        return e == null
            ? s.registrarCompra(mes, valor)
            : s.editarCompra(mes, e.id, valor);
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final e = widget.editar;
    final tipo = textoTipo(_ticker.text);
    final resumo = _resumo();
    final subtitulo = e != null && e.vendas.isNotEmpty
        ? 'Já vendidas: ${vendido(e)}'
        : 'Dados da compra';
    return QuadroFormulario(
      dialogo: widget.dialogo,
      titulo: e != null ? 'Editar compra' : 'Novo ativo',
      erro: erro,
      salvando: salvando,
      aoSalvar: _salvar,
      children: [
        Text(subtitulo, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        TextField(
          key: const ValueKey('ticker'),
          controller: _ticker,
          autofocus: (_ini['ticker'] ?? '').isEmpty,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Ticker',
            hintText: 'Ex.: PETR4',
          ),
          onChanged: (_) => setState(() {}),
        ),
        ChipsTicker(
          tickers: _frequentes,
          marcado: _tickerAtual,
          aoEscolher: _escolher,
        ),
        if (tipo != null)
          Text(
            tipo,
            style: TextStyle(
              color: c.textoSuave,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        CampoData(
          valor: _data,
          maximo: _maximo,
          aoMudar: (d) => setState(() => _data = d),
        ),
        TextField(
          key: const ValueKey('qtd'),
          controller: _qtd,
          focusNode: _focoQtd,
          autofocus: (_ini['ticker'] ?? '').isNotEmpty,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quantidade',
            hintText: 'Ex.: 100',
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          key: const ValueKey('preco'),
          controller: _preco,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Preço unitário (R\$)',
            hintText: 'Ex.: 32,50',
          ),
          onChanged: (_) => setState(() {}),
        ),
        PainelResumoOrdem(
          resumo: resumo,
          nota: resumo == null ? '' : notaResumoCompra,
        ),
      ],
    );
  }
}
