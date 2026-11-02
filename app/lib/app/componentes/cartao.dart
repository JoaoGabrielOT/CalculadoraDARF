// Peças visuais simples: cartão, selo, pílula, indicador (KPI), chip de filtro
// e botão segmentado. Cores só pelos tokens de `CoresApp`.

import 'package:flutter/material.dart';

import '../tema/cores_app.dart';

/// Fundo do chip comum: no tema Moderno o token é translúcido.
Color _fundoChip(CoresApp c) => Color.alphaBlend(c.chipFundo, c.fundo);

class Cartao extends StatelessWidget {
  const Cartao({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.cartao,
        borderRadius: BorderRadius.circular(c.raioCartao),
        border: c.cartaoBorda.a == 0 ? null : Border.all(color: c.cartaoBorda),
        boxShadow: c.sombraCartao,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Variação em destaque: [alta] true = alta, false = queda, null = neutro.
/// O sentido vai também no texto (o chamador inclui o sinal ou a seta).
class Selo extends StatelessWidget {
  const Selo({super.key, required this.texto, this.alta});

  final String texto;
  final bool? alta;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final (fundo, cor) = switch (alta) {
      true => (c.seloAltaFundo, c.alta),
      false => (c.seloQuedaFundo, c.queda),
      null => (_fundoChip(c), c.textoSuave),
    };
    return _Rotulo(texto: texto, fundo: fundo, cor: cor);
  }
}

/// Rótulo arredondado de uma informação (por exemplo, "Isento").
class Pilula extends StatelessWidget {
  const Pilula({super.key, required this.texto, this.fundo, this.cor});

  final String texto;
  final Color? fundo;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return _Rotulo(
      texto: texto,
      fundo: fundo ?? _fundoChip(c),
      cor: cor ?? c.chipTexto,
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo({required this.texto, required this.fundo, required this.cor});

  final String texto;
  final Color fundo;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          texto,
          style: TextStyle(
            color: cor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Título pequeno, valor grande e uma linha de apoio opcional.
class Kpi extends StatelessWidget {
  const Kpi({
    super.key,
    required this.titulo,
    required this.valor,
    this.sub = '',
    this.corValor,
  });

  final String titulo;
  final String valor;
  final String sub;
  final Color? corValor;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            color: corValor ?? c.texto,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (sub.isNotEmpty)
          Text(sub, style: TextStyle(color: c.textoSuave, fontSize: 12)),
      ],
    );
  }
}

/// Chip de filtro ou de escolha. O selecionado muda de cor e ganha o ícone de
/// marcação e o texto em negrito, para continuar distinguível sem depender da
/// cor (três temas, daltonismo) e para o leitor de tela (`selected`).
class ChipFiltro extends StatelessWidget {
  const ChipFiltro({
    super.key,
    required this.rotulo,
    required this.selecionado,
    required this.aoTocar,
  });

  final String rotulo;
  final bool selecionado;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cor = selecionado ? c.chipAtivoTexto : c.chipTexto;
    return Semantics(
      button: true,
      selected: selecionado,
      enabled: aoTocar != null,
      label: rotulo,
      excludeSemantics: true,
      onTap: aoTocar,
      child: Material(
        color: selecionado ? c.chipAtivoFundo : _fundoChip(c),
        shape: StadiumBorder(
          side: BorderSide(
            color: selecionado
                ? (c.chipAtivoBorda ?? c.chipAtivoFundo)
                : c.bordaCampo,
            width: selecionado ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: aoTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selecionado) ...[
                    Icon(Icons.check, size: 16, color: cor),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    rotulo,
                    style: TextStyle(
                      color: cor,
                      fontSize: 13,
                      fontWeight: selecionado
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

/// Escolha de uma opção entre poucas, lado a lado: [opcoes] são pares
/// (valor, rótulo).
class BotaoSegmentado<T> extends StatelessWidget {
  const BotaoSegmentado({
    super.key,
    required this.opcoes,
    required this.valor,
    required this.aoMudar,
  });

  final List<(T, String)> opcoes;
  final T valor;
  final ValueChanged<T> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, rotulo) in opcoes)
          ChipFiltro(
            rotulo: rotulo,
            selecionado: v == valor,
            aoTocar: () => aoMudar(v),
          ),
      ],
    );
  }
}
