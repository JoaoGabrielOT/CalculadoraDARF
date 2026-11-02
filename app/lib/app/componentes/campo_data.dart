// Campo de data: texto dd/mm/aaaa editável, calendário e atalhos Hoje/Ontem
// (android/main.py:292-350; componentes.py:71-204). Os valores são ISO
// (AAAA-MM-DD).

import 'package:flutter/material.dart';

import '../../nucleo/nucleo.dart';
import 'cartao.dart';
import 'dialogos.dart';

class CampoData extends StatefulWidget {
  const CampoData({
    super.key,
    this.valor,
    this.minimo,
    this.maximo,
    this.permitido,
    required this.aoMudar,
  });

  final String? valor;
  final String? minimo;
  final String? maximo;

  /// Bloqueia dias dentro dos limites (componentes.py: `filtro`).
  final bool Function(String iso)? permitido;

  /// Chamado com a data escolhida; null quando o texto é apagado.
  final ValueChanged<String?> aoMudar;

  @override
  State<CampoData> createState() => _CampoDataState();
}

class _CampoDataState extends State<CampoData> {
  late final TextEditingController _texto = TextEditingController(
    text: _formatar(widget.valor),
  );
  String? _erro;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CampoData antigo) {
    super.didUpdateWidget(antigo);
    // Valor trocado de fora (limites, outro formulário): reflete no texto,
    // a menos que o texto digitado já seja esse valor.
    if (widget.valor != antigo.valor && _ler(_texto.text) != widget.valor) {
      _texto.text = _formatar(widget.valor);
      _erro = null;
    }
  }

  static String _formatar(String? iso) => iso == null ? '' : fmtData(iso);

  static String? _ler(String texto) {
    try {
      return parseData(texto);
    } on FormatException {
      return null;
    }
  }

  bool _permite(String iso) =>
      (widget.minimo == null || iso.compareTo(widget.minimo!) >= 0) &&
      (widget.maximo == null || iso.compareTo(widget.maximo!) <= 0) &&
      (widget.permitido?.call(iso) ?? true);

  void _digitou(String texto) {
    final t = texto.trim();
    if (t.isEmpty) {
      setState(() => _erro = null);
      if (widget.valor != null) widget.aoMudar(null);
      return;
    }
    final iso = _ler(t);
    if (iso == null) {
      // Ainda digitando (ou texto inválido): o valor não muda; só avisa
      // quando o texto já tem o tamanho de uma data completa.
      setState(() => _erro = t.length >= 10 ? 'Data inválida.' : null);
      return;
    }
    if (!_permite(iso)) {
      setState(() => _erro = 'Data fora do período permitido.');
      return;
    }
    setState(() => _erro = null);
    if (iso != widget.valor) widget.aoMudar(iso);
  }

  void _definir(String iso) {
    _texto.text = fmtData(iso);
    setState(() => _erro = null);
    widget.aoMudar(iso);
  }

  Future<void> _abrirCalendario() async {
    final hoje = ambiente.hoje();
    final inicio = widget.minimo ?? '2000-01-01';
    final fim = widget.maximo ?? hoje;
    final inicial = _diaInicial(widget.valor ?? hoje, inicio, fim);
    if (inicial == null) {
      await avisar(context, 'Atenção', 'Não há data válida neste período.');
      return;
    }
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(inicial),
      firstDate: DateTime.parse(inicio),
      lastDate: DateTime.parse(fim),
      currentDate: DateTime.parse(hoje),
      selectableDayPredicate: (d) => _permite(isoDeDateTime(d)),
      helpText: 'Selecione a data',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (d != null) _definir(isoDeDateTime(d));
  }

  /// Dia permitido mais próximo de [desejado] dentro de [inicio, fim]; o
  /// `showDatePicker` exige que o dia inicial seja selecionável.
  String? _diaInicial(String desejado, String inicio, String fim) {
    if (inicio.compareTo(fim) > 0) return null;
    var base = desejado;
    if (base.compareTo(inicio) < 0) base = inicio;
    if (base.compareTo(fim) > 0) base = fim;
    for (var i = 0; i < 4000; i++) {
      for (final candidato in [somarDias(base, -i), somarDias(base, i)]) {
        if (candidato.compareTo(inicio) >= 0 &&
            candidato.compareTo(fim) <= 0 &&
            _permite(candidato)) {
          return candidato;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hoje = ambiente.hoje();
    final ontem = somarDias(hoje, -1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _texto,
          keyboardType: TextInputType.datetime,
          onChanged: _digitou,
          decoration: InputDecoration(
            labelText: 'Data',
            hintText: 'dd/mm/aaaa',
            errorText: _erro,
            suffixIcon: IconButton(
              tooltip: 'Abrir calendário',
              icon: const Icon(Icons.calendar_month),
              onPressed: _abrirCalendario,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final (rotulo, iso) in [('Hoje', hoje), ('Ontem', ontem)])
              if (_permite(iso))
                ChipFiltro(
                  rotulo: rotulo,
                  selecionado: widget.valor == iso,
                  aoTocar: () => _definir(iso),
                ),
          ],
        ),
      ],
    );
  }
}
