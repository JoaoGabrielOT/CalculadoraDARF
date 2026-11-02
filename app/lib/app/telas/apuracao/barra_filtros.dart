// Barra de filtros das listas de compras e vendas: busca, filtros, ordenação,
// sentido e Limpar (android/main.py:867-912). Nas duas larguras; no expandido
// a Situação das compras vira o botão segmentado do Windows
// (calculadora_darf.py:1366-1374).

import 'package:flutter/material.dart';

import '../../componentes/cartao.dart';
import '../../regras/filtros.dart';
import '../../tema/cores_app.dart';

/// Um filtro de escolha única; [opcoes] são pares (valor, rótulo).
class MenuFiltro {
  const MenuFiltro({
    required this.chave,
    required this.titulo,
    required this.opcoes,
    required this.valor,
    required this.padrao,
  });

  final String chave;
  final String titulo;
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

/// Barra das compras; [segmentada] troca o chip Situação pelo botão segmentado.
class BarraFiltrosLotes extends StatelessWidget {
  const BarraFiltrosLotes({
    super.key,
    required this.filtro,
    required this.aoMudar,
    required this.segmentada,
  });

  final FiltroLotes filtro;
  final ValueChanged<FiltroLotes> aoMudar;
  final bool segmentada;

  @override
  Widget build(BuildContext context) {
    return BarraFiltros(
      id: 'lotes',
      menus: [
        if (!segmentada)
          MenuFiltro(
            chave: 'situacao',
            titulo: 'Situação',
            opcoes: _pares(_situacoes),
            valor: filtro.situacao,
            padrao: 'Todos',
          ),
        MenuFiltro(
          chave: 'tipo',
          titulo: 'Tipo',
          opcoes: _pares(_tipos),
          valor: filtro.tipo,
          padrao: 'Todos',
        ),
      ],
      situacao: segmentada
          ? _Situacao(
              valor: filtro.situacao,
              aoMudar: (v) => aoMudar(filtro.copiarCom(situacao: v)),
            )
          : null,
      ordens: ordensLotes,
      ordemPadrao: 'cadastro',
      ordem: filtro.ordem,
      desc: filtro.desc,
      busca: filtro.busca,
      filtrado: filtro.filtrado,
      aoDefinir: (chave, v) => aoMudar(switch (chave) {
        'situacao' => filtro.copiarCom(situacao: v),
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
          opcoes: _pares(_operacoes),
          valor: filtro.operacao,
          padrao: 'Todas',
        ),
        MenuFiltro(
          chave: 'tipo',
          titulo: 'Tipo',
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

class _Situacao extends StatelessWidget {
  const _Situacao({required this.valor, required this.aoMudar});

  final String valor;
  final ValueChanged<String> aoMudar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'SITUAÇÃO',
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        BotaoSegmentado<String>(
          opcoes: _pares(_situacoes),
          valor: valor,
          aoMudar: aoMudar,
        ),
      ],
    );
  }
}

/// Linha de chips e o campo de busca quando aberto. O campo de busca é daqui
/// (um `TextEditingController`), para o foco não se perder ao filtrar.
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
  final Widget? situacao;
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
  late bool _buscando = widget.busca.isNotEmpty;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _alternarBusca() {
    setState(() {
      _buscando = !_buscando;
      if (!_buscando) {
        _campo.clear();
        widget.aoBuscar('');
      }
    });
  }

  void _limpar() {
    setState(() {
      _buscando = false;
      _campo.clear();
    });
    widget.aoLimpar();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    final buscaAtiva = _buscando || widget.busca.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ?widget.situacao,
            Tooltip(
              message: 'Buscar ticker',
              child: ChipFiltro(
                key: Key('chip-$id-busca'),
                rotulo: 'Buscar',
                selecionado: buscaAtiva,
                aoTocar: _alternarBusca,
              ),
            ),
            for (final m in widget.menus)
              _ChipMenu(
                key: Key('chip-$id-${m.chave}'),
                titulo: m.titulo,
                opcoes: m.opcoes,
                valor: m.valor,
                ativo: m.valor != m.padrao,
                aoEscolher: (v) => widget.aoDefinir(m.chave, v),
              ),
            _ChipMenu(
              key: Key('chip-$id-ordem'),
              titulo: 'Ordenar',
              opcoes: widget.ordens,
              valor: widget.ordem,
              ativo: widget.ordem != widget.ordemPadrao,
              sempreValor: true,
              aoEscolher: (v) => widget.aoDefinir('ordem', v),
            ),
            ChipFiltro(
              key: Key('inverter-$id'),
              rotulo: widget.desc ? 'Decrescente ↓' : 'Crescente ↑',
              selecionado: false,
              aoTocar: widget.aoInverter,
            ),
            if (widget.filtrado)
              ChipFiltro(
                key: Key('limpar-$id'),
                rotulo: 'Limpar',
                selecionado: false,
                aoTocar: _limpar,
              ),
          ],
        ),
        if (buscaAtiva)
          TextField(
            key: Key('busca-$id'),
            controller: _campo,
            autofocus: widget.busca.isEmpty,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Buscar ticker',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: widget.aoBuscar,
          ),
      ],
    );
  }
}

/// Chip que abre um menu de escolha única (android/main.py:217-225).
class _ChipMenu extends StatelessWidget {
  const _ChipMenu({
    super.key,
    required this.titulo,
    required this.opcoes,
    required this.valor,
    required this.ativo,
    required this.aoEscolher,
    this.sempreValor = false,
  });

  final String titulo;
  final List<(String, String)> opcoes;
  final String valor;
  final bool ativo;
  final bool sempreValor;
  final ValueChanged<String> aoEscolher;

  Future<void> _abrir(BuildContext context) async {
    final caixa = context.findRenderObject() as RenderBox;
    final sobreposicao =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final topo = caixa.localToGlobal(
      Offset(0, caixa.size.height),
      ancestor: sobreposicao,
    );
    final escolhido = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        topo.dx,
        topo.dy,
        sobreposicao.size.width - topo.dx,
        sobreposicao.size.height - topo.dy,
      ),
      items: [
        for (final (v, rotulo) in opcoes)
          PopupMenuItem<String>(
            value: v,
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: v == valor ? null : Colors.transparent,
                ),
                Text(rotulo),
              ],
            ),
          ),
      ],
    );
    if (escolhido != null) aoEscolher(escolhido);
  }

  @override
  Widget build(BuildContext context) {
    final rotuloValor = {for (final (v, r) in opcoes) v: r}[valor] ?? valor;
    return ChipFiltro(
      rotulo: ativo || sempreValor ? '$titulo: $rotuloValor' : titulo,
      selecionado: ativo,
      aoTocar: () => _abrir(context),
    );
  }
}
