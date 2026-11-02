// Formulário do saldo em conta: definir, aporte ou retirada
// (calculadora_darf.py:538-580; android/main.py:1627-1681).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../regras/formularios.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import 'abrir_formulario.dart';

/// Nulo quando o usuário cancela. Sem saldo definido só "Definir saldo" existe.
Future<VisaoCaixa?> abrirFormSaldo(
  BuildContext c,
  ResumoCaixa r,
  ModoSaldo modo,
) => abrirFormulario<VisaoCaixa>(
  c,
  (dialogo) => FormSaldo(resumo: r, modo: modo, dialogo: dialogo),
);

class FormSaldo extends StatefulWidget {
  const FormSaldo({
    super.key,
    required this.resumo,
    required this.modo,
    required this.dialogo,
  });

  final ResumoCaixa resumo;
  final ModoSaldo modo;
  final bool dialogo;

  @override
  State<FormSaldo> createState() => _FormSaldoState();
}

class _FormSaldoState extends State<FormSaldo>
    with SalvarFormulario<FormSaldo, VisaoCaixa> {
  late ModoSaldo _modo;
  late final TextEditingController _valor;

  @override
  void initState() {
    super.initState();
    final r = widget.resumo;
    _modo = r.definido ? widget.modo : ModoSaldo.definir;
    _valor = TextEditingController(
      text: r.definido && _modo == ModoSaldo.definir
          ? precoTexto(r.disponivel)
          : '',
    );
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  static String _nome(ModoSaldo m) => switch (m) {
    ModoSaldo.definir => 'Definir saldo',
    ModoSaldo.aporte => 'Aporte',
    ModoSaldo.retirada => 'Retirada',
  };

  void _trocar(ModoSaldo m) {
    setState(() {
      _modo = m;
      if (m != ModoSaldo.definir) _valor.clear();
    });
  }

  Future<void> _salvar() => salvarCom(() async {
    switch (validarSaldo(_modo, _valor.text)) {
      case Invalido(:final mensagem):
        erro = mensagem;
        return null;
      case Valido(:final valor):
        final (modo, v) = valor;
        return context.read<ServicosApp>().alterarSaldo(modo, v);
    }
  });

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final r = widget.resumo;
    final definir = _modo == ModoSaldo.definir;
    final titulo = switch (widget.modo) {
      ModoSaldo.aporte => 'Aporte',
      ModoSaldo.retirada => 'Retirada',
      ModoSaldo.definir => 'Saldo em conta',
    };
    final suave = TextStyle(color: c.textoSuave, fontSize: 12);
    return QuadroFormulario(
      dialogo: widget.dialogo,
      titulo: titulo,
      erro: erro,
      salvando: salvando,
      aoSalvar: _salvar,
      children: [
        Text(
          r.definido
              ? 'Saldo disponível hoje: ${brl(r.disponivel)}'
              : 'Informe o saldo livre na conta da corretora hoje.',
          style: suave,
        ),
        BotaoSegmentado<ModoSaldo>(
          opcoes: [
            for (final m in r.definido ? ModoSaldo.values : [ModoSaldo.definir])
              (m, _nome(m)),
          ],
          valor: _modo,
          aoMudar: _trocar,
        ),
        TextField(
          key: const ValueKey('valor'),
          controller: _valor,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: definir
                ? 'Saldo disponível hoje (R\$)'
                : 'Valor do ${_nome(_modo).toLowerCase()} (R\$)',
            hintText: 'Ex.: 10.000,00',
          ),
        ),
        Text(
          definir
              ? 'Use o saldo livre que a corretora mostra hoje, já com as '
                    'liquidações de hoje.'
              : _modo == ModoSaldo.aporte
              ? 'Soma ao saldo disponível.'
              : 'Desconta do saldo disponível.',
          style: suave,
        ),
      ],
    );
  }
}
