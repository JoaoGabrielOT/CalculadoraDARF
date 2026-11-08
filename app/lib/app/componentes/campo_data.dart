// Campo de data: texto dd/mm/aaaa editável, calendário e atalhos Hoje/Ontem
// (android/main.py:292-350; componentes.py:71-204). Os valores são ISO
// (AAAA-MM-DD). Aceita a data com ou sem barras (ddmmaaaa) e põe as barras
// enquanto se digita.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;

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

  /// Chamado com a data escolhida; null quando o texto fica vazio, inválido
  /// ou fora do período (o formulário deve bloquear o salvar).
  final ValueChanged<String?> aoMudar;

  @override
  State<CampoData> createState() => _CampoDataState();
}

class _CampoDataState extends State<CampoData> {
  late final TextEditingController _texto = TextEditingController(
    text: _formatar(widget.valor),
  );
  final FocusNode _foco = FocusNode();
  String? _erro;

  @override
  void initState() {
    super.initState();
    _foco.addListener(_aoMudarFoco);
  }

  @override
  void dispose() {
    // Sem o ouvinte, perder o foco ao desmontar não chama setState.
    _foco.removeListener(_aoMudarFoco);
    _foco.dispose();
    _texto.dispose();
    super.dispose();
  }

  /// Ao sair do campo, texto incompleto ou impossível ganha o erro.
  void _aoMudarFoco() {
    final t = _texto.text.trim();
    if (!_foco.hasFocus && t.isNotEmpty && _ler(t) == null) {
      setState(() => _erro = 'Data inválida.');
    }
  }

  @override
  void didUpdateWidget(CampoData antigo) {
    super.didUpdateWidget(antigo);
    // Valor trocado de fora (limites, outro formulário): reflete no texto,
    // a menos que o texto digitado já seja esse valor. Valor null não apaga
    // um texto que o próprio campo recusou (inválido ou fora do período).
    if (widget.valor == antigo.valor) return;
    final digitado = _ler(_texto.text);
    final apagar = widget.valor == null
        ? digitado != null && _permite(digitado)
        : digitado != widget.valor;
    if (apagar) {
      _texto.text = _formatar(widget.valor);
      _erro = null;
    }
  }

  static String _formatar(String? iso) => iso == null ? '' : fmtData(iso);

  static String? _ler(String texto) {
    final t = texto.trim();
    try {
      // ddmmaaaa: oito dígitos sem barras
      if (_soDigitos.hasMatch(t)) {
        return parseData(
          '${t.substring(0, 2)}/${t.substring(2, 4)}/${t.substring(4)}',
        );
      }
      return parseData(t);
    } on FormatException {
      return null;
    }
  }

  // Os mesmos limites valem para o texto e para o calendário.
  String get _minimo => widget.minimo ?? '2000-01-01';
  String get _maximo => widget.maximo ?? ambiente.hoje();

  bool _permite(String iso) =>
      iso.compareTo(_minimo) >= 0 &&
      iso.compareTo(_maximo) <= 0 &&
      (widget.permitido?.call(iso) ?? true);

  static final _soDigitos = RegExp(r'^\d{8}$');
  static final _formatoCompleto = RegExp(r'^(\d{1,2}/\d{1,2}/\d{4}|\d{8})$');

  /// Texto vazio, inválido ou fora do período não deixa a data antiga valendo:
  /// o pai recebe null (o formulário bloqueia o salvar).
  void _digitou(String texto) {
    final t = texto.trim();
    final iso = _ler(t);
    String? erro;
    if (t.isNotEmpty && iso == null) {
      // Ainda digitando: sem erro até sair do campo, a menos que o texto já
      // tenha o formato completo (30/2/2026).
      erro = _formatoCompleto.hasMatch(t) ? 'Data inválida.' : null;
    } else if (iso != null && !_permite(iso)) {
      erro = 'Data fora do período permitido.';
    }
    setState(() => _erro = erro);
    final valido = iso != null && erro == null;
    if (valido) {
      if (iso != widget.valor) widget.aoMudar(iso);
    } else if (widget.valor != null) {
      widget.aoMudar(null);
    }
  }

  void _definir(String iso) {
    _texto.text = fmtData(iso);
    setState(() => _erro = null);
    widget.aoMudar(iso);
  }

  Future<void> _abrirCalendario() async {
    final hoje = ambiente.hoje();
    final inicio = _minimo;
    final fim = _maximo;
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
          focusNode: _foco,
          keyboardType: TextInputType.datetime,
          inputFormatters: const [BarrasData()],
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

/// Põe as barras de dd/mm/aaaa enquanto se digita no fim do texto: "081"
/// vira "08/1" e "08112026" vira "08/11/2026". Só mexe quando as barras que
/// já existem estão nessas posições, então "5/10/2026" fica como está; ao
/// apagar (o texto novo é começo do antigo), nada é recolocado.
class BarrasData extends TextInputFormatter {
  const BarrasData();

  static final _digitosEBarras = RegExp(r'^[\d/]*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antigo,
    TextEditingValue novo,
  ) {
    final t = novo.text;
    final noFim =
        novo.selection.isCollapsed && novo.selection.baseOffset == t.length;
    if (!noFim || antigo.text.startsWith(t) || !_digitosEBarras.hasMatch(t)) {
      return novo;
    }
    var digitos = t.replaceAll('/', '');
    if (digitos.length > 8) digitos = digitos.substring(0, 8);
    final b = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(digitos[i]);
    }
    final mascarado = b.toString();
    // barra fora das posições 2 e 5 (dia ou mês de um dígito, ou "08/"
    // digitado com a barra): o texto fica como o usuário escreveu
    for (var i = 0; i < t.length; i++) {
      if (t[i] == '/' && (i >= mascarado.length || mascarado[i] != '/')) {
        return novo;
      }
    }
    return TextEditingValue(
      text: mascarado,
      selection: TextSelection.collapsed(offset: mascarado.length),
    );
  }
}
