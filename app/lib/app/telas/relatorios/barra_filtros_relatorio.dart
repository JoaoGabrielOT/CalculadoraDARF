// Barra de pesquisa e filtros antes do "Resumo por ativo": busca por texto e
// chips de tipo e de status. No celular os chips ficam recolhidos atrás do
// botão "Filtros (N)". O estado do filtro fica em quem usa a barra; ela só
// mostra o filtro e avisa a mudança.

import 'package:flutter/material.dart';

import '../../../nucleo/relatorios/filtros_relatorio.dart';
import '../../../nucleo/relatorios/relatorio.dart';
import '../../componentes/cartao.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';

const textoSemAtivosFiltrados = 'Nenhum ativo com esses filtros';

/// acao→"Ações", bdr→"BDRs", fii→"FIIs", fiagro→"Fiagro"; outro, o texto cru.
String rotuloTipo(String chave) => switch (chave) {
  'acao' => 'Ações',
  'bdr' => 'BDRs',
  'fii' => 'FIIs',
  'fiagro' => 'Fiagro',
  _ => chave,
};

const _rotuloLeitura = {
  Leitura.positiva: 'Positivas',
  Leitura.mista: 'Mistas',
  Leitura.neutra: 'Neutras',
  Leitura.negativa: 'Negativas',
};

/// Tipos presentes nos [ativos], na ordem em que aparecem.
List<String> tiposPresentes(List<AtivoRelatorio> ativos) =>
    {for (final a in ativos) ?chaveTipo(a)}.toList();

class BarraFiltrosRelatorio extends StatefulWidget {
  const BarraFiltrosRelatorio({
    super.key,
    required this.filtro,
    required this.aoMudar,
    required this.tipos,
    required this.mostrarCarteira,
    required this.exibidos,
    required this.total,
  });

  final FiltroAtivos filtro;
  final ValueChanged<FiltroAtivos> aoMudar;
  final List<String> tipos;

  /// false quando as posições não carregaram: o chip some.
  final bool mostrarCarteira;
  final int exibidos;
  final int total;

  @override
  State<BarraFiltrosRelatorio> createState() => _EstadoBarra();
}

class _EstadoBarra extends State<BarraFiltrosRelatorio> {
  bool _aberto = false;

  late final TextEditingController _campo = TextEditingController(
    text: widget.filtro.texto,
  );

  @override
  void didUpdateWidget(BarraFiltrosRelatorio antigo) {
    super.didUpdateWidget(antigo);
    // "Limpar filtros" (ou outro dono do filtro) esvazia o campo.
    if (widget.filtro.texto != _campo.text) _campo.text = widget.filtro.texto;
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  FiltroAtivos get _f => widget.filtro;

  /// Filtros dos chips que estão ligados (a busca não conta: está à vista).
  int get _ativos =>
      _f.tipos.length +
      _f.leituras.length +
      (_f.comAnalise != null ? 1 : 0) +
      (_f.soDestaque ? 1 : 0) +
      (_f.soCarteira ? 1 : 0);

  Set<T> _alternar<T>(Set<T> s, T v) =>
      s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  Widget _chip(String chave, String rotulo, bool sel, VoidCallback aoTocar) =>
      ChipFiltro(
        key: Key(chave),
        rotulo: rotulo,
        selecionado: sel,
        aoTocar: aoTocar,
      );

  List<Widget> _chips() => [
    if (widget.tipos.isNotEmpty)
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in widget.tipos)
            _chip(
              'chip-tipo-$t',
              rotuloTipo(t),
              _f.tipos.contains(t),
              () => widget.aoMudar(_f.copiar(tipos: _alternar(_f.tipos, t))),
            ),
        ],
      ),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in Leitura.values)
          _chip(
            'chip-leitura-${l.name}',
            _rotuloLeitura[l]!,
            _f.leituras.contains(l),
            () =>
                widget.aoMudar(_f.copiar(leituras: _alternar(_f.leituras, l))),
          ),
        _chip(
          'chip-destaque',
          'Em destaque',
          _f.soDestaque,
          () => widget.aoMudar(_f.copiar(soDestaque: !_f.soDestaque)),
        ),
        _chip(
          'chip-com-analise',
          'Com análise',
          _f.comAnalise == true,
          () => widget.aoMudar(
            _f.copiar(comAnalise: () => _f.comAnalise == true ? null : true),
          ),
        ),
        _chip(
          'chip-sem-analise',
          'Sem análise',
          _f.comAnalise == false,
          () => widget.aoMudar(
            _f.copiar(comAnalise: () => _f.comAnalise == false ? null : false),
          ),
        ),
        if (widget.mostrarCarteira)
          _chip(
            'chip-carteira',
            'Na minha carteira',
            _f.soCarteira,
            () => widget.aoMudar(_f.copiar(soCarteira: !_f.soCarteira)),
          ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final recolhivel = !expandido(context);
    final campo = TextField(
      key: const Key('filtro-busca'),
      controller: _campo,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar ativo',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: _campo.text.isEmpty
            ? null
            : IconButton(
                key: const Key('filtro-busca-limpar'),
                tooltip: 'Limpar busca',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _campo.clear();
                  widget.aoMudar(_f.copiar(texto: ''));
                },
              ),
      ),
      onChanged: (s) => widget.aoMudar(_f.copiar(texto: s)),
    );
    return Cartao(
      key: const Key('filtros-ativos'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (recolhivel)
            Row(
              spacing: 8,
              children: [
                Expanded(child: campo),
                OutlinedButton.icon(
                  key: const Key('filtros-alternar'),
                  onPressed: () => setState(() => _aberto = !_aberto),
                  icon: Icon(_aberto ? Icons.expand_less : Icons.expand_more),
                  label: Text('Filtros ($_ativos)'),
                ),
              ],
            )
          else
            campo,
          if (!recolhivel || _aberto) ..._chips(),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${widget.exibidos} de ${widget.total} ativos',
                key: const Key('filtro-contagem'),
                style: TextStyle(color: c.textoSuave, fontSize: 13),
              ),
              if (!_f.vazio)
                TextButton(
                  key: const Key('filtro-limpar'),
                  onPressed: () {
                    _campo.clear();
                    widget.aoMudar(const FiltroAtivos());
                  },
                  child: const Text('Limpar filtros'),
                ),
            ],
          ),
          if (widget.exibidos == 0)
            Text(
              textoSemAtivosFiltrados,
              key: const Key('filtro-vazio'),
              style: TextStyle(color: c.textoSuave),
            ),
        ],
      ),
    );
  }
}
