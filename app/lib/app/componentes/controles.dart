// Kit de controles: botões, escolha única, busca, menus, seletor de mês e
// selos. Altura de 40 px no PC e 48 px no celular; cores só pelos tokens de
// `CoresApp`. Os nomes `Selo` daqui e de cartao.dart coexistem até as telas
// migrarem (não importar os dois no mesmo arquivo).

import 'package:flutter/material.dart';

import '../../nucleo/datas.dart';
import '../tema/cores_app.dart';
import '../tema/layout.dart';

double _altura(BuildContext context) => expandido(context) ? 40.0 : 48.0;

/// Altura fixa, sem a área de toque extra do Material (que somaria 8 px).
ButtonStyle _estilo(BuildContext context) => ButtonStyle(
  fixedSize: WidgetStatePropertyAll(Size.fromHeight(_altura(context))),
  minimumSize: WidgetStatePropertyAll(Size(0, _altura(context))),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

class BotaoPrincipal extends StatelessWidget {
  const BotaoPrincipal({
    super.key,
    required this.icone,
    required this.rotulo,
    this.onPressed,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: _estilo(context),
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: Text(rotulo),
  );
}

class BotaoSecundario extends StatelessWidget {
  const BotaoSecundario({
    super.key,
    required this.icone,
    required this.rotulo,
    this.onPressed,
    this.compacto = false,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? onPressed;
  final bool compacto;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: _estilo(context).copyWith(
      padding: compacto
          ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10))
          : null,
    ),
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: Text(rotulo),
  );
}

/// Botão só de ícone: o tooltip serve também de rótulo para o leitor de tela.
class BotaoIcone extends StatelessWidget {
  const BotaoIcone({
    super.key,
    required this.icone,
    required this.tooltip,
    this.onPressed,
    this.destrutivo = false,
    this.marcado = false,
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destrutivo;

  /// Ponto no canto, para um filtro ativo.
  final bool marcado;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final h = _altura(context);
    final botao = IconButton(
      onPressed: onPressed,
      // desabilitado, fica com a cor apagada do tema, como os outros
      icon: Icon(
        icone,
        size: 20,
        color: destrutivo && onPressed != null ? c.queda : null,
      ),
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(h)),
        minimumSize: WidgetStatePropertyAll(Size.square(h)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
    );
    // O tooltip do Material só vira `tooltip` semântico, não rótulo: o
    // rótulo explícito faz o leitor de tela falar o nome do botão.
    // O rótulo se funde (MergeSemantics) ao nó do IconButton, que mantém as
    // ações de toque e foco; o Tooltip fica fora da semântica para não
    // duplicar o texto.
    final comRotulo = MergeSemantics(
      child: Semantics(
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          excludeFromSemantics: true,
          child: botao,
        ),
      ),
    );
    if (!marcado) return comRotulo;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        comRotulo,
        Positioned(
          top: 8,
          right: 8,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('ponto-marcado'),
                decoration: BoxDecoration(
                  color: c.destaque,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.fundo, width: 1.5),
                ),
                child: const SizedBox.square(dimension: 9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ação de baixa ênfase (texto com ícone); o rótulo longo vira reticências.
class BotaoLeve extends StatelessWidget {
  const BotaoLeve({
    super.key,
    required this.icone,
    required this.rotulo,
    this.onPressed,
    this.cor,
    this.larguraMaxRotulo = 180,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? onPressed;
  final Color? cor;
  final double larguraMaxRotulo;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    style: _estilo(context).copyWith(
      foregroundColor: cor == null ? null : WidgetStatePropertyAll(cor),
    ),
    onPressed: onPressed,
    icon: Icon(icone, size: 18),
    label: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: larguraMaxRotulo),
      child: Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

/// Escolha única entre poucas opções, lado a lado. [compacto] tira o ✓ e
/// aperta a margem (cabe mais opções em 360 px).
class Segmentado<T> extends StatelessWidget {
  const Segmentado({
    super.key,
    required this.opcoes,
    required this.valor,
    required this.aoMudar,
    this.compacto = false,
    this.expandir = false,
    this.chaveOpcao,
  });

  final List<(T, String)> opcoes;
  final T valor;
  final ValueChanged<T> aoMudar;
  final bool compacto;

  /// Ocupa a largura toda do pai, com as opções repartidas.
  final bool expandir;
  final Key Function(T)? chaveOpcao;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _altura(context),
    child: SegmentedButton<T>(
      showSelectedIcon: !compacto,
      expandedInsets: expandir ? EdgeInsets.zero : null,
      // O SegmentedButton ignora fixedSize: a altura é 40 mais o ajuste da
      // densidade vertical; 1,75 dá exatamente 48 no segmento (medido: 2 dá
      // 50 e 1,5 dá 46).
      style: ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity(vertical: expandido(context) ? 0 : 1.75),
        padding: compacto
            ? const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10))
            : null,
      ),
      segments: [
        for (final (v, rotulo) in opcoes)
          ButtonSegment<T>(
            value: v,
            label: Text(rotulo, key: chaveOpcao?.call(v)),
          ),
      ],
      selected: {valor},
      // tocar na opção já escolhida a "desmarca" (conjunto vazio) e avisa
      // com ela mesma, como o BotaoSegmentado: há escolhas que valem mesmo
      // iguais ao padrão; o valor continua vindo de fora
      emptySelectionAllowed: true,
      onSelectionChanged: (s) => aoMudar(s.isEmpty ? valor : s.first),
    ),
  );
}

/// Campo de busca com lupa e, havendo texto, botão de limpar.
class CampoBusca extends StatelessWidget {
  const CampoBusca({
    super.key,
    required this.controller,
    required this.dica,
    this.aoMudar,
    this.largura,
  });

  final TextEditingController controller;
  final String dica;
  final ValueChanged<String>? aoMudar;
  final double? largura;

  @override
  Widget build(BuildContext context) {
    final h = _altura(context);
    final c = CoresApp.de(context);
    final restricao = BoxConstraints.tightFor(width: h, height: h);
    return SizedBox(
      width: largura,
      height: h,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => TextField(
          controller: controller,
          onChanged: aoMudar,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: dica,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            prefixIcon: Icon(Icons.search, size: 20, color: c.textoSuave),
            prefixIconConstraints: restricao,
            suffixIconConstraints: restricao,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      controller.clear();
                      aoMudar?.call('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Abre um menu ancorado embaixo do widget de [context]. Cada item age pelo
/// próprio `onTap`; o valor devolvido pelo menu não é usado.
Future<void> abrirMenuAncorado<T>(
  BuildContext context,
  List<PopupMenuEntry<T>> entradas,
) {
  final caixa = context.findRenderObject()! as RenderBox;
  final sobreposicao =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final topoEsq = caixa.localToGlobal(
    Offset(0, caixa.size.height),
    ancestor: sobreposicao,
  );
  final baixoDir = caixa.localToGlobal(
    caixa.size.bottomRight(Offset.zero),
    ancestor: sobreposicao,
  );
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(topoEsq, baixoDir),
      Offset.zero & sobreposicao.size,
    ),
    items: entradas,
  );
}

/// Item de menu com a coluna do ✓ (marcado ou vazia, para alinhar os textos).
PopupMenuItem<T> itemMenu<T>(
  T valor,
  String texto, {
  required bool marcado,
  required VoidCallback aoTocar,
  Key? chave,
}) => PopupMenuItem<T>(
  key: chave,
  value: valor,
  onTap: aoTocar,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 22,
        child: marcado ? const Icon(Icons.check, size: 16) : null,
      ),
      Flexible(child: Text(texto)),
    ],
  ),
);

/// Botão que abre uma lista de opções; [marcado] leva o ✓. Com [soIcone],
/// [ativo] desenha o ponto de filtro fora do padrão.
class BotaoMenu<T> extends StatelessWidget {
  const BotaoMenu({
    super.key,
    required this.icone,
    required this.rotulo,
    required this.itens,
    required this.aoEscolher,
    this.marcado,
    this.soIcone = false,
    this.ativo = false,
  });

  final IconData icone;
  final String rotulo;
  final List<(T, String)> itens;
  final ValueChanged<T> aoEscolher;
  final T? marcado;
  final bool soIcone;
  final bool ativo;

  @override
  Widget build(BuildContext context) => _GatilhoMenu<T>(
    icone: icone,
    rotulo: rotulo,
    tooltip: rotulo,
    soIcone: soIcone,
    ativo: ativo,
    entradas: () => [
      for (final (v, texto) in itens)
        itemMenu<T>(
          v,
          texto,
          marcado: v == marcado,
          aoTocar: () => aoEscolher(v),
        ),
    ],
  );
}

/// Ordenação: o rótulo mostra o campo e a direção; o menu troca o campo e,
/// havendo [aoInverter], inverte a direção. [ativo] como em [BotaoMenu].
class BotaoOrdenar<T> extends StatelessWidget {
  const BotaoOrdenar({
    super.key,
    required this.campos,
    required this.campo,
    this.desc = false,
    required this.aoCampo,
    this.aoInverter,
    this.soIcone = false,
    this.ativo = false,
    this.chaveItem,
    this.chaveInverter,
  });

  final List<(T, String)> campos;
  final T campo;
  final bool desc;
  final ValueChanged<T> aoCampo;
  final VoidCallback? aoInverter;
  final bool soIcone;
  final bool ativo;
  final Key Function(T)? chaveItem;
  final Key? chaveInverter;

  @override
  Widget build(BuildContext context) {
    final nome = campos.firstWhere((p) => p.$1 == campo).$2;
    final seta = aoInverter == null ? '' : (desc ? ' ↓' : ' ↑');
    return _GatilhoMenu<T>(
      icone: Icons.swap_vert,
      rotulo: '$nome$seta',
      tooltip: 'Ordenar',
      soIcone: soIcone,
      ativo: ativo,
      entradas: () => [
        for (final (v, texto) in campos)
          itemMenu<T>(
            v,
            texto,
            marcado: v == campo,
            aoTocar: () => aoCampo(v),
            chave: chaveItem?.call(v),
          ),
        if (aoInverter != null) ...[
          const PopupMenuDivider(),
          itemMenu<T>(
            campo,
            desc ? 'Crescente ↑' : 'Decrescente ↓',
            marcado: false,
            aoTocar: aoInverter!,
            chave: chaveInverter,
          ),
        ],
      ],
    );
  }
}

class _GatilhoMenu<T> extends StatelessWidget {
  const _GatilhoMenu({
    required this.icone,
    required this.rotulo,
    required this.tooltip,
    required this.soIcone,
    required this.ativo,
    required this.entradas,
  });

  final IconData icone;
  final String rotulo;
  final String tooltip;
  final bool soIcone;
  final bool ativo;
  final List<PopupMenuEntry<T>> Function() entradas;

  @override
  Widget build(BuildContext context) {
    // O Builder faz o menu ancorar no botão, não no widget inteiro.
    return Builder(
      builder: (ctx) {
        void abrir() => abrirMenuAncorado<T>(ctx, entradas());
        if (soIcone) {
          return BotaoIcone(
            icone: icone,
            tooltip: tooltip,
            marcado: ativo,
            onPressed: abrir,
          );
        }
        return Tooltip(
          message: tooltip,
          child: OutlinedButton.icon(
            style: _estilo(ctx),
            onPressed: abrir,
            icon: Icon(icone, size: 18),
            label: Text(rotulo),
          ),
        );
      },
    );
  }
}

/// Caixa contornada com rótulo flutuante que abre uma lista; [aoMudar] nulo
/// deixa o campo desabilitado.
class SeletorCaixa<T> extends StatelessWidget {
  const SeletorCaixa({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.itens,
    this.aoMudar,
    this.largura,
  });

  final String rotulo;
  final T valor;
  final List<(T, String)> itens;
  final ValueChanged<T>? aoMudar;
  final double? largura;

  @override
  Widget build(BuildContext context) {
    final h = _altura(context);
    final c = CoresApp.de(context);
    final ativo = aoMudar != null;
    final atual = itens.where((p) => p.$1 == valor).map((p) => p.$2);
    return SizedBox(
      width: largura,
      height: h,
      child: Builder(
        builder: (ctx) => InkWell(
          borderRadius: BorderRadius.circular(c.raioCartao),
          onTap: ativo
              ? () => abrirMenuAncorado<T>(ctx, [
                  for (final (v, texto) in itens)
                    itemMenu<T>(
                      v,
                      texto,
                      marcado: v == valor,
                      aoTocar: () => aoMudar!(v),
                    ),
                ])
              : null,
          child: InputDecorator(
            isEmpty: false,
            isFocused: false,
            decoration: InputDecoration(
              labelText: rotulo,
              enabled: ativo,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: (h - 20) / 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    atual.isEmpty ? '' : atual.first,
                    maxLines: 1,
                    style: TextStyle(color: ativo ? c.texto : c.textoSuave),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 20, color: c.textoSuave),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _somaMes(String mes, int delta) {
  final p = mes.split('-');
  final i = int.parse(p[0]) * 12 + int.parse(p[1]) - 1 + delta;
  return '${(i ~/ 12).toString().padLeft(4, '0')}-'
      '${(i % 12 + 1).toString().padLeft(2, '0')}';
}

/// ◂ mês ▸: as setas andam um mês (`AAAA-MM`); o centro abre a grade.
class SeletorMes extends StatelessWidget {
  const SeletorMes({
    super.key,
    required this.mes,
    required this.maximo,
    required this.aoMudar,
    required this.aoAbrir,
  });

  final String mes;
  final String maximo;
  final ValueChanged<String> aoMudar;
  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    final h = _altura(context);
    final noMaximo = mes.compareTo(maximo) >= 0;
    // pílula contornada; o recorte segura o efeito do toque dentro dela
    return Material(
      type: MaterialType.transparency,
      shape: StadiumBorder(
        side: BorderSide(color: CoresApp.de(context).bordaCampo),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: h,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BotaoIcone(
              icone: Icons.chevron_left,
              tooltip: 'Mês anterior',
              onPressed: () => aoMudar(_somaMes(mes, -1)),
            ),
            TextButton(
              style: _estilo(context),
              onPressed: aoAbrir,
              child: Text(
                fmtMes(mes),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            BotaoIcone(
              icone: Icons.chevron_right,
              tooltip: 'Próximo mês',
              onPressed: noMaximo ? null : () => aoMudar(_somaMes(mes, 1)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta chapada: fundo da [cor] a 18%, texto na [cor], sem borda.
class Selo extends StatelessWidget {
  const Selo({
    super.key,
    required this.texto,
    required this.cor,
    this.icone,
    this.ponto = false,
  });

  final String texto;
  final Color cor;
  final IconData? icone;
  final bool ponto;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: cor.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ponto) ...[_Ponto(cor), const SizedBox(width: 6)],
          if (icone != null) ...[
            Icon(icone, size: 14, color: cor),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              texto,
              style: TextStyle(
                color: cor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Legenda não clicável: ponto colorido e texto suave. Com [detalhe], o
/// texto vira o nome (linha 1) e o detalhe fica na linha 2, e o ponto
/// acompanha a primeira linha.
class LegendaPonto extends StatelessWidget {
  const LegendaPonto({
    super.key,
    required this.texto,
    required this.cor,
    this.detalhe,
  });

  final String texto;
  final Color cor;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final suave = CoresApp.de(context).textoSuave;
    final estilo = TextStyle(color: suave, fontSize: 12);
    final d = detalhe;
    // quebra em vez de estourar quando a coluna é estreita
    final corpo = d == null
        ? Text(texto, style: estilo)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(texto, style: estilo.copyWith(fontWeight: FontWeight.w700)),
              Text(d, style: estilo),
            ],
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: d == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: d == null ? 0 : 4),
          child: _Ponto(cor),
        ),
        const SizedBox(width: 6),
        Flexible(child: corpo),
      ],
    );
  }
}

class _Ponto extends StatelessWidget {
  const _Ponto(this.cor);

  final Color cor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
    child: const SizedBox.square(dimension: 8),
  );
}
