// Barra de filtros das listas de compras e vendas: Situação segmentada (só
// compras), busca, menus de filtro, Ordenar e Limpar (android/main.py:867-912;
// calculadora_darf.py:1366-1374). No PC, uma linha que quebra; no celular, a
// Situação em cima e a busca expandida com os menus em ícone embaixo.

import 'package:flutter/material.dart';

import '../../componentes/controles.dart';
import '../../regras/filtros.dart';
import '../../tema/layout.dart';

/// Um filtro de escolha única; [opcoes] são pares (valor, rótulo).
class MenuFiltro {
  const MenuFiltro({
    required this.chave,
    required this.titulo,
    required this.icone,
    required this.opcoes,
    required this.valor,
    required this.padrao,
  });

  final String chave;
  final String titulo;
  final IconData icone;
  final List<(String, String)> opcoes;
  final String valor;
  final String padrao;
}

const ordensLotes = [
  ('cadastro', 'Cadastro'),
  ('data', 'Data da compra'),
  ('ticker', 'Ticker'),
  ('qtd', 'Quantidade'),
  ('preco', 'Preço de compra'),
  ('atual', 'Preço atual'),
  ('total', 'Total'),
  ('resultado', 'Ganho/perda'),
  ('restante', 'Restante'),
];

const ordensVendas = [
  ('data', 'Data da venda'),
  ('ticker', 'Ticker'),
  ('qtd', 'Quantidade'),
  ('preco', 'Preço de venda'),
  ('bruto', 'Lucro bruto'),
  ('liquido', 'Após taxas'),
  ('imposto', 'Imposto'),
  ('taxas', 'Taxas B3'),
];

const _situacoes = ['Todos', 'Em aberto', 'Vendidos'];
const _tipos = ['Todos', 'Ação', 'BDR'];
const _operacoes = ['Todas', 'Swing', 'Day trade'];

List<(String, String)> _pares(List<String> v) => [for (final x in v) (x, x)];

/// Barra das compras.
class BarraFiltrosLotes extends StatelessWidget {
  const BarraFiltrosLotes({
    super.key,
    required this.filtro,
    required this.aoMudar,
  });

  final FiltroLotes filtro;
  final ValueChanged<FiltroLotes> aoMudar;

  @override
  Widget build(BuildContext context) {
    return BarraFiltros(
      id: 'lotes',
      menus: [
        MenuFiltro(
          chave: 'tipo',
          titulo: 'Tipo',
          icone: Icons.filter_list,
          opcoes: _pares(_tipos),
          valor: filtro.tipo,
          padrao: 'Todos',
        ),
      ],
      situacao: (
        opcoes: _pares(_situacoes),
        valor: filtro.situacao,
        aoMudar: (v) => aoMudar(filtro.copiarCom(situacao: v)),
      ),
      ordens: ordensLotes,
      ordemPadrao: 'cadastro',
      ordem: filtro.ordem,
      desc: filtro.desc,
      busca: filtro.busca,
      filtrado: filtro.filtrado,
      aoDefinir: (chave, v) => aoMudar(switch (chave) {
        'tipo' => filtro.copiarCom(tipo: v),
        _ => filtro.copiarCom(ordem: v, desc: descPadrao(v)),
      }),
      aoBuscar: (v) => aoMudar(filtro.copiarCom(busca: v)),
      aoInverter: () => aoMudar(filtro.copiarCom(desc: !filtro.desc)),
      aoLimpar: () => aoMudar(FiltroLotes()),
    );
  }
}

class BarraFiltrosVendas extends StatelessWidget {
  const BarraFiltrosVendas({
    super.key,
    required this.filtro,
    required this.aoMudar,
  });

  final FiltroVendas filtro;
  final ValueChanged<FiltroVendas> aoMudar;

  @override
  Widget build(BuildContext context) {
    return BarraFiltros(
      id: 'vendas',
      menus: [
        MenuFiltro(
          chave: 'operacao',
          titulo: 'Operação',
          icone: Icons.schedule,
          opcoes: _pares(_operacoes),
          valor: filtro.operacao,
          padrao: 'Todas',
        ),
        MenuFiltro(
          chave: 'tipo',
          titulo: 'Tipo',
          icone: Icons.filter_list,
          opcoes: _pares(_tipos),
          valor: filtro.tipo,
          padrao: 'Todos',
        ),
      ],
      ordens: ordensVendas,
      ordemPadrao: 'data',
      ordem: filtro.ordem,
      desc: filtro.desc,
      busca: filtro.busca,
      filtrado: filtro.filtrado,
      aoDefinir: (chave, v) => aoMudar(switch (chave) {
        'operacao' => filtro.copiarCom(operacao: v),
        'tipo' => filtro.copiarCom(tipo: v),
        _ => filtro.copiarCom(ordem: v, desc: descPadrao(v)),
      }),
      aoBuscar: (v) => aoMudar(filtro.copiarCom(busca: v)),
      aoInverter: () => aoMudar(filtro.copiarCom(desc: !filtro.desc)),
      aoLimpar: () => aoMudar(FiltroVendas()),
    );
  }
}

/// Os controles dos filtros. O campo de busca é daqui (um
/// `TextEditingController`), para o foco não se perder ao filtrar.
class BarraFiltros extends StatefulWidget {
  const BarraFiltros({
    super.key,
    required this.id,
    required this.menus,
    required this.ordens,
    required this.ordemPadrao,
    required this.ordem,
    required this.desc,
    required this.busca,
    required this.filtrado,
    required this.aoDefinir,
    required this.aoBuscar,
    required this.aoInverter,
    required this.aoLimpar,
    this.situacao,
  });

  final String id;
  final List<MenuFiltro> menus;

  /// Escolha única segmentada antes da busca (a Situação das compras).
  final ({
    List<(String, String)> opcoes,
    String valor,
    ValueChanged<String> aoMudar,
  })?
  situacao;
  final List<(String, String)> ordens;
  final String ordemPadrao;
  final String ordem;
  final bool desc;
  final String busca;
  final bool filtrado;

  /// [chave] é a do menu ou 'ordem'.
  final void Function(String chave, String valor) aoDefinir;
  final ValueChanged<String> aoBuscar;
  final VoidCallback aoInverter;
  final VoidCallback aoLimpar;

  @override
  State<BarraFiltros> createState() => _BarraFiltrosState();
}

class _BarraFiltrosState extends State<BarraFiltros> {
  late final TextEditingController _campo = TextEditingController(
    text: widget.busca,
  );

  @override
  void didUpdateWidget(BarraFiltros antigo) {
    super.didUpdateWidget(antigo);
    // o filtro limpo por fora (Limpar, outra lista) zera o campo
    if (widget.busca != _campo.text) _campo.text = widget.busca;
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _limpar() {
    _campo.clear();
    widget.aoLimpar();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, caixa) => _montar(context, caixa.maxWidth),
  );

  /// PC: uma linha com a busca flexível; se os rótulos de Tipo e Ordenar não
  /// couberem, eles viram ícone; se nem assim, fica o arranjo do celular
  /// (a Situação em cima). Celular: sempre esse arranjo.
  Widget _montar(BuildContext context, double largura) {
    final id = widget.id;
    final grande = expandido(context);
    final sit = widget.situacao;
    final rotulosMenus = [
      for (final m in widget.menus)
        m.valor == m.padrao
            ? m.titulo
            : '${m.titulo}: ${_rotulo(m.opcoes, m.valor)}',
    ];
    final rotuloOrdem =
        '${_rotulo(widget.ordens, widget.ordem)} ${widget.desc ? '↓' : '↑'}';
    // larguras estimadas pelo texto; a busca (flexível, de 160 px para cima)
    // absorve o erro da estimativa
    final estilo = DefaultTextStyle.of(context).style
        .copyWith(fontSize: 14, fontWeight: FontWeight.w500);
    final escala = MediaQuery.textScalerOf(context);
    double texto(String t) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: estilo),
        textDirection: TextDirection.ltr,
        textScaler: escala,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    const espaco = 8.0;
    const buscaMinima = 160.0;
    final pecas = (sit == null ? 0 : 1) + widget.menus.length + 1;
    final larguraSituacao = sit == null
        ? 0.0
        : sit.opcoes.fold(0.0, (s, o) => s + texto(o.$2) + 26) + 30;
    final larguraLimpar = widget.filtrado ? texto('Limpar') + 60 + espaco : 0.0;
    final fixo = larguraSituacao + buscaMinima + larguraLimpar + pecas * espaco;
    final umaLinha =
        grande && fixo + (pecas - (sit == null ? 0 : 1)) * 40 <= largura;
    final comRotulo =
        umaLinha &&
        fixo +
                [
                  ...rotulosMenus,
                  rotuloOrdem,
                ].fold(0.0, (s, r) => s + texto(r) + 70) <=
            largura;
    final soIcone = !comRotulo;
    final situacao = sit == null
        ? null
        : Segmentado<String>(
            opcoes: sit.opcoes,
            valor: sit.valor,
            aoMudar: sit.aoMudar,
            compacto: !grande,
          );
    final busca = CampoBusca(
      key: Key('busca-$id'),
      controller: _campo,
      dica: 'Buscar ticker…',
      aoMudar: widget.aoBuscar,
    );
    final menus = [
      for (final (i, m) in widget.menus.indexed)
        BotaoMenu<String>(
          key: Key('chip-$id-${m.chave}'),
          icone: m.icone,
          rotulo: soIcone ? m.titulo : rotulosMenus[i],
          itens: m.opcoes,
          marcado: m.valor,
          aoEscolher: (v) => widget.aoDefinir(m.chave, v),
          soIcone: soIcone,
          ativo: m.valor != m.padrao,
        ),
    ];
    final ordenar = BotaoOrdenar<String>(
      key: Key('chip-$id-ordem'),
      campos: widget.ordens,
      campo: widget.ordem,
      desc: widget.desc,
      aoCampo: (v) => widget.aoDefinir('ordem', v),
      aoInverter: widget.aoInverter,
      soIcone: soIcone,
      ativo:
          widget.ordem != widget.ordemPadrao ||
          widget.desc != descPadrao(widget.ordem),
      chaveInverter: Key('inverter-$id'),
    );
    final limpar = widget.filtrado
        ? BotaoLeve(
            key: Key('limpar-$id'),
            icone: Icons.filter_alt_off,
            rotulo: 'Limpar',
            onPressed: _limpar,
          )
        : null;
    if (umaLinha) {
      return Row(
        spacing: espaco,
        children: [
          ?situacao,
          Expanded(child: busca),
          ...menus,
          ordenar,
          ?limpar,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: espaco,
      children: [
        ?situacao,
        Row(
          spacing: espaco,
          children: [
            Expanded(child: busca),
            ...menus,
            ordenar,
          ],
        ),
        if (limpar != null)
          Align(alignment: Alignment.centerRight, child: limpar),
      ],
    );
  }
}

String _rotulo(List<(String, String)> opcoes, String valor) =>
    {for (final (v, r) in opcoes) v: r}[valor] ?? valor;
