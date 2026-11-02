// Seletor de mês: grade de 12 meses por ano (android/main.py:1086-1125;
// componentes.py:205-261). Meses são `AAAA-MM`.

import 'package:flutter/material.dart';

import '../../nucleo/nucleo.dart';
import '../tema/layout.dart';
import '../tema/cores_app.dart';

const _mesesCurtos = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

/// Devolve o mês escolhido, ou null se fechar. Meses depois de [maximo] ficam
/// desabilitados; meses anteriores sem arquivo podem ser escolhidos.
Future<String?> escolherMes(
  BuildContext c, {
  required String atual,
  required Set<String> comDados,
  required String maximo,
}) {
  return showDialog<String>(
    context: c,
    builder: (_) =>
        _SeletorMes(atual: atual, comDados: comDados, maximo: maximo),
  );
}

class _SeletorMes extends StatefulWidget {
  const _SeletorMes({
    required this.atual,
    required this.comDados,
    required this.maximo,
  });

  final String atual;
  final Set<String> comDados;
  final String maximo;

  @override
  State<_SeletorMes> createState() => _SeletorMesState();
}

class _SeletorMesState extends State<_SeletorMes> {
  late int _ano = int.parse(widget.atual.substring(0, 4));

  String _mes(int i) =>
      '${_ano.toString().padLeft(4, '0')}-'
      '${(i + 1).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final proximoAno = '${(_ano + 1).toString().padLeft(4, '0')}-01';
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Ano anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _ano--),
          ),
          Text('$_ano'),
          IconButton(
            tooltip: 'Próximo ano',
            icon: const Icon(Icons.chevron_right),
            onPressed: proximoAno.compareTo(widget.maximo) > 0
                ? null
                : () => setState(() => _ano++),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 12; i++)
                  _CelulaMes(
                    nome: _mesesCurtos[i],
                    ano: _ano,
                    aberto: _mes(i) == widget.atual,
                    comDados: widget.comDados.contains(_mes(i)),
                    futuro: _mes(i).compareTo(widget.maximo) > 0,
                    aoTocar: () => Navigator.pop(context, _mes(i)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Verde: meses com operações',
              style: TextStyle(color: c.textoSuave, fontSize: 11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            // O mês de hoje, a menos que o máximo seja anterior a ele.
            final hoje = ambiente.hoje().substring(0, 7);
            Navigator.pop(
              context,
              hoje.compareTo(widget.maximo) > 0 ? widget.maximo : hoje,
            );
          },
          child: const Text('Mês atual'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

/// O mês aberto leva o ícone de marcação e o fundo de destaque; o mês com
/// operações leva um ponto e o negrito, além da cor.
class _CelulaMes extends StatelessWidget {
  const _CelulaMes({
    required this.nome,
    required this.ano,
    required this.aberto,
    required this.comDados,
    required this.futuro,
    required this.aoTocar,
  });

  final String nome;
  final int ano;
  final bool aberto;
  final bool comDados;
  final bool futuro;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cor = aberto ? c.chipAtivoTexto : (comDados ? c.alta : c.texto);
    final habilitado = !futuro;
    return Semantics(
      button: true,
      selected: aberto,
      enabled: habilitado,
      label: '$nome $ano${comDados ? ', com operações' : ''}',
      excludeSemantics: true,
      onTap: habilitado ? aoTocar : null,
      child: Opacity(
        opacity: futuro ? 0.35 : 1,
        child: Material(
          color: aberto ? c.chipAtivoFundo : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: aberto
                  ? (c.chipAtivoBorda ?? c.chipAtivoFundo)
                  : (comDados ? c.alta : c.bordaCampo),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: habilitado ? aoTocar : null,
            child: SizedBox(
              width: 90,
              height: expandido(context) ? 44 : 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (aberto) ...[
                    Icon(Icons.check, size: 16, color: cor),
                    const SizedBox(width: 4),
                  ] else if (comDados) ...[
                    Icon(Icons.circle, size: 8, color: cor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    nome,
                    style: TextStyle(
                      color: cor,
                      fontWeight: aberto || comDados
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
