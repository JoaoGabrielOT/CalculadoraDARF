// Tela Radar: topo com a legenda de risco, filtros, ordem e resumo do dia, e a
// lista dos ativos com as cotações que chegam uma a uma (calculadora_darf.py:
// 1991-2054; android/main.py:1682-1867). A lista nunca espera a rede: cada
// linha mostra o que já chegou, "—" ou o erro dela.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../componentes/controles.dart' hide Selo;
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../../tema/temas.dart';
import '../grafico/tela_grafico.dart';
import 'controle_radar.dart';
import 'linha_radar.dart';

/// Troca a abertura do gráfico do ativo (os testes); sem ele, tocar na linha
/// abre `abrirGrafico`.
typedef AbrirGraficoRadar = void Function(
  BuildContext c, {
  required String ticker,
  required String nome,
  DadosAtivo? dados,
  bool amigo,
  bool jaTenho,
});

const _faixasRotulo = ['< 2,2%', '2,2% a 3,0%', '3,0% a 4,5%', '> 4,5%'];

/// ATR% de exemplo dentro de cada faixa de `classificarRisco`.
const _atrDaFaixa = [1.0, 2.5, 4.0, 5.0];

class TelaRadar extends StatelessWidget {
  const TelaRadar({super.key, this.aoAbrirGrafico});

  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleRadar>(
      create: (c) => ControleRadar(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: _Corpo(aoAbrirGrafico: aoAbrirGrafico),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({required this.aoAbrirGrafico});

  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleRadar>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: expandido(context)
          ? _Expandido(controle: controle, aoAbrirGrafico: aoAbrirGrafico)
          : _Compacto(controle: controle, aoAbrirGrafico: aoAbrirGrafico),
    );
  }
}

/// O que cada botão da linha faz, pelo dono da lista.
AcoesRadar _acoes(
  BuildContext c,
  ControleRadar controle,
  ItemRadar item,
  AbrirGraficoRadar? abrir,
) {
  final t = item.ticker;
  final amigo = controle.amigo != null;
  final visao = controle.visao;
  final meus = visao?.meus ?? const <String>{};
  final cotacao = controle.cotacoes[t];
  final dados = cotacao is CotacaoOk ? cotacao.dados : null;
  final nome = item.nome.isNotEmpty ? item.nome : (dados?.nome ?? '');
  final comprar = amigo ? null : () => unawaited(controle.comprar(c, t));
  final vender = amigo || !(visao?.custodia.contains(t) ?? false)
      ? null
      : () => unawaited(controle.vender(c, t));
  final importar = amigo && !meus.contains(t)
      ? () => unawaited(controle.importar(c, t))
      : null;
  return AcoesRadar(
    aoAbrir: () => abrir != null
        ? abrir(
            c,
            ticker: t,
            nome: nome,
            dados: dados,
            amigo: amigo,
            jaTenho: meus.contains(t),
          )
        : unawaited(
            abrirGrafico(
              c,
              ticker: t,
              nome: nome,
              dados: dados,
              amigo: amigo,
              jaTenho: meus.contains(t),
              aoComprar: comprar,
              aoVender: vender,
              aoImportar: importar,
              aoVerNoticias: () => c.read<EstadoApp>().verNoticias(t),
            ),
          ),
    aoComprar: comprar,
    aoVender: vender,
    aoRemover: amigo ? null : () => unawaited(controle.remover(c, t)),
    aoImportar: importar,
  );
}

/// Faixa fina de progresso: o carregamento nunca cobre a tela.
class _Progresso extends StatelessWidget {
  const _Progresso(this.ativo);

  final bool ativo;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 3,
    child: ativo
        ? const LinearProgressIndicator(key: ValueKey('progresso-tela'))
        : null,
  );
}

/// Erro de carga, com o resto da tela ainda à mão.
class _Erro extends StatelessWidget {
  const _Erro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.aviso.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: c.aviso),
              const SizedBox(width: 12),
              Expanded(child: Semantics(liveRegion: true, child: Text(texto))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vazio da lista, ou null quando há o que mostrar (py:2331-2338).
String? _textoVazio(ControleRadar c) {
  if (c.visao == null) return null;
  if (c.itens.isEmpty) {
    final amigo = c.amigo;
    return amigo != null
        ? '$amigo não tem ativos no radar.'
        : 'Nenhum ativo no radar. Adicione um ticker acima.';
  }
  if (c.lista.isEmpty) return 'Nenhum ativo com esse filtro.';
  return null;
}

String _titulo(ControleRadar c) {
  final amigo = c.amigo;
  return amigo != null ? 'Radar de $amigo' : 'Radar de Ações';
}

/// Status da atualização; vira aviso quando a alça não pode arrastar.
class _Status extends StatelessWidget {
  const _Status(this.controle);

  final ControleRadar controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Semantics(
      liveRegion: controle.statusAviso,
      child: Text(
        controle.status,
        key: const Key('status-radar'),
        style: TextStyle(
          color: controle.statusAviso ? c.aviso : c.textoSuave,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// "RISCO PELO ATR%" e as quatro faixas (py:2007-2012): título numa linha
/// própria; as faixas, numa linha no PC e numa grade de 2 colunas iguais no
/// celular.
class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final faixas = [
      for (final (i, atr) in _atrDaFaixa.indexed)
        () {
          final risco = classificarRisco(atr);
          return LegendaPonto(
            texto: '${risco.rotulo} · ${_faixasRotulo[i]}',
            cor: corFaixaRisco(risco) ?? c.textoSuave,
          );
        }(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          'RISCO PELO ATR%',
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (expandido(context))
          Wrap(spacing: 20, runSpacing: 6, children: faixas)
        else
          for (var i = 0; i < faixas.length; i += 2)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Expanded(child: faixas[i]),
                Expanded(child: faixas[i + 1]),
              ],
            ),
      ],
    );
  }
}

/// Mostrar (filtro), Ordenar e o resumo do dia.
class _Filtros extends StatelessWidget {
  const _Filtros(this.controle);

  final ControleRadar controle;

  @override
  Widget build(BuildContext context) {
    final (altas, quedas, media) = controle.resumo;
    final grande = expandido(context);
    final segmentado = Segmentado<String>(
      opcoes: [for (final f in filtrosRadar) (f, f)],
      valor: controle.filtro,
      aoMudar: controle.definirFiltro,
      compacto: !grande,
    );
    Widget ordenar({required bool soIcone}) => BotaoOrdenar<String>(
      key: const Key('menu-ordem'),
      campos: ordensRadar,
      campo: ordensRadar.any((o) => o.$1 == controle.ordem)
          ? controle.ordem
          : ordensRadar.first.$1,
      aoCampo: (k) => unawaited(controle.definirOrdem(k)),
      soIcone: soIcone,
    );
    final resumo = media == null
        ? null
        : Text(
            'Hoje: $altas em alta · $quedas em queda · média ${fmtPct(media)}',
            key: const Key('resumo-dia'),
            style: TextStyle(
              color: corVariacao(context, media),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          );
    if (!grande) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          segmentado,
          Align(
            alignment: Alignment.centerLeft,
            child: ordenar(soIcone: false),
          ),
          ?resumo,
        ],
      );
    }
    // os dois controles andam juntos; se não couberem com o rótulo, o
    // Ordenar vira ícone (nenhum fica sozinho numa linha)
    return LayoutBuilder(
      builder: (context, caixa) => Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              segmentado,
              ordenar(soIcone: caixa.maxWidth < 640),
            ],
          ),
          ?resumo,
        ],
      ),
    );
  }
}

/// Campo do ticker e "+  Adicionar" (só nos meus dados).
class _Adicionar extends StatefulWidget {
  const _Adicionar({required this.controle, required this.compacto});

  final ControleRadar controle;
  final bool compacto;

  @override
  State<_Adicionar> createState() => _AdicionarState();
}

class _AdicionarState extends State<_Adicionar> {
  final _campo = TextEditingController();

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final ok = await widget.controle.adicionar(context, _campo.text);
    if (ok && mounted) _campo.clear();
  }

  @override
  Widget build(BuildContext context) {
    final campo = SizedBox(
      height: 40,
      child: TextField(
        key: const Key('campo-ticker'),
        controller: _campo,
        textCapitalization: TextCapitalization.characters,
        textAlignVertical: TextAlignVertical.center,
        // preenche os 40 px: o contorno acompanha a altura do campo
        expands: true,
        maxLines: null,
        minLines: null,
        onSubmitted: (_) => unawaited(_enviar()),
        decoration: InputDecoration(
          hintText: widget.compacto
              ? 'Adicionar ticker (ex.: VALE3)'
              : 'Ticker (ex.: VALE3)',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
    );
    if (widget.compacto) {
      return Row(
        spacing: 8,
        children: [
          Expanded(child: campo),
          IconButton.filled(
            onPressed: () => unawaited(_enviar()),
            icon: const Icon(Icons.add),
            tooltip: 'Adicionar',
            style: IconButton.styleFrom(
              fixedSize: const Size.square(40),
              minimumSize: const Size.square(40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        SizedBox(width: 220, child: campo),
        BotaoPrincipal(
          icone: Icons.add,
          rotulo: 'Adicionar',
          onPressed: () => unawaited(_enviar()),
        ),
      ],
    );
  }
}

/// Importar os ativos do amigo que ainda não tenho.
class _ImportarTodos extends StatelessWidget {
  const _ImportarTodos({required this.controle, required this.compacto});

  final ControleRadar controle;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    if (!compacto) {
      return BotaoPrincipal(
        icone: Icons.playlist_add,
        rotulo: 'Importar todos para o meu radar',
        onPressed: () => unawaited(controle.importarTodos(context)),
      );
    }
    final faltam = controle.novosDoAmigo.length;
    return BotaoPrincipal(
      icone: Icons.playlist_add,
      rotulo: faltam == 0
          ? 'Todos já estão no seu radar'
          : 'Importar $faltam para o meu radar',
      onPressed: faltam == 0
          ? null
          : () => unawaited(controle.importarTodos(context)),
    );
  }
}

// --- expandido (Windows)

class _Expandido extends StatelessWidget {
  const _Expandido({required this.controle, required this.aoAbrirGrafico});

  final ControleRadar controle;
  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    final amigo = controle.amigo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Progresso(controle.carregando),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Cartao(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _titulo(controle),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _Status(controle),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (amigo == null)
                          _Adicionar(controle: controle, compacto: false)
                        else
                          _ImportarTodos(controle: controle, compacto: false),
                        BotaoIcone(
                          icone: Icons.refresh,
                          tooltip: 'Atualizar',
                          onPressed: () =>
                              unawaited(controle.atualizar(forcar: true)),
                        ),
                      ],
                    ),
                  ],
                ),
                const _Legenda(),
                _Filtros(controle),
              ],
            ),
          ),
        ),
        if (controle.erro != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _Erro(controle.erro!),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Cartao(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: _Tabela(
                controle: controle,
                aoAbrirGrafico: aoAbrirGrafico,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cabeçalho e linhas; abaixo da largura mínima a tabela rola na horizontal.
class _Tabela extends StatelessWidget {
  const _Tabela({required this.controle, required this.aoAbrirGrafico});

  final ControleRadar controle;
  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final vazio = _textoVazio(controle);
    final Widget corpo;
    if (controle.visao == null) {
      corpo = controle.erro == null ? const Carregando() : const SizedBox();
    } else if (vazio != null) {
      corpo = Center(
        child: Text(vazio, style: TextStyle(color: c.textoSuave)),
      );
    } else {
      corpo = _ListaExpandida(
        controle: controle,
        aoAbrirGrafico: aoAbrirGrafico,
      );
    }
    return LayoutBuilder(
      builder: (context, caixa) {
        final tabela = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CabecalhoRadar(comAlca: controle.amigo == null),
            Divider(height: 1, color: c.linha),
            Expanded(child: corpo),
          ],
        );
        if (caixa.maxWidth >= larguraMinimaTabelaRadar) return tabela;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: larguraMinimaTabelaRadar, child: tabela),
        );
      },
    );
  }
}

class _ListaExpandida extends StatelessWidget {
  const _ListaExpandida({required this.controle, required this.aoAbrirGrafico});

  final ControleRadar controle;
  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    final lista = controle.lista;
    final amigo = controle.amigo != null;
    final manual = controle.reordenavel;
    Widget Function(Widget)? alca(int i, String t) {
      if (amigo) return null;
      if (manual) {
        // alça: arrasta na hora; o toque nela não abre o gráfico
        return (icone) => ReorderableDragStartListener(
          index: i,
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: GestureDetector(
              key: Key('alca-$t'),
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: icone,
            ),
          ),
        );
      }
      return (icone) => GestureDetector(
        key: Key('alca-$t'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => controle.avisarArrastar(),
        child: icone,
      );
    }

    Widget linha(BuildContext c, int i) {
      final item = lista[i];
      final t = item.ticker;
      return Padding(
        key: ValueKey('radar-$t'),
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: LinhaRadar(
          item: item,
          cotacao: controle.cotacoes[t],
          mini: controle.minis[t],
          zebra: i.isOdd,
          amigo: amigo,
          alca: alca(i, t),
          acoes: _acoes(c, controle, item, aoAbrirGrafico),
        ),
      );
    }

    const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 4);
    if (manual) {
      return ReorderableListView.builder(
        key: const Key('lista-radar'),
        padding: padding,
        buildDefaultDragHandles: false,
        itemCount: lista.length,
        itemBuilder: linha,
        onReorderItem: (de, para) => unawaited(controle.reordenar(de, para)),
      );
    }
    return ListView.builder(
      key: const Key('lista-radar'),
      padding: padding,
      itemCount: lista.length,
      itemBuilder: linha,
    );
  }
}

// --- compacto (celular)

class _Compacto extends StatelessWidget {
  const _Compacto({required this.controle, required this.aoAbrirGrafico});

  final ControleRadar controle;
  final AbrirGraficoRadar? aoAbrirGrafico;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final amigo = controle.amigo;
    final vazio = _textoVazio(controle);
    final lista = controle.visao == null ? const <ItemRadar>[] : controle.lista;
    final dica = amigo == null && lista.length > 1
        ? (controle.reordenavel
              ? 'Toque para ver o gráfico. Toque e segure e arraste para '
                    'mudar a ordem.'
              : 'Toque para ver o gráfico. Para arrastar, use Ordenar: Minha '
                    'ordem.')
        : null;
    final topo = Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _Progresso(controle.carregando),
          Cartao(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _titulo(controle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    BotaoIcone(
                      icone: Icons.refresh,
                      tooltip: 'Atualizar',
                      onPressed: () =>
                          unawaited(controle.atualizar(forcar: true)),
                    ),
                  ],
                ),
                _Status(controle),
                if (amigo == null)
                  _Adicionar(controle: controle, compacto: true)
                else
                  _ImportarTodos(controle: controle, compacto: true),
                const _Legenda(),
              ],
            ),
          ),
          _Filtros(controle),
          if (controle.erro != null) _Erro(controle.erro!),
          if (vazio != null) Text(vazio, style: TextStyle(color: c.textoSuave)),
          if (dica != null)
            Text(dica, style: TextStyle(color: c.textoSuave, fontSize: 12)),
        ],
      ),
    );
    final rodape = controle.visao == null && controle.erro == null
        ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Carregando(),
          )
        : const SizedBox(height: 24);

    Widget cartao(BuildContext ctx, int i) {
      final item = lista[i];
      final t = item.ticker;
      final cartao = CartaoRadar(
        item: item,
        cotacao: controle.cotacoes[t],
        mini: controle.minis[t],
        amigo: amigo != null,
        comAlca: amigo == null,
        acoes: _acoes(ctx, controle, item, aoAbrirGrafico),
      );
      return Padding(
        key: ValueKey('radar-$t'),
        padding: const EdgeInsets.only(bottom: 12),
        child: controle.reordenavel
            ? ReorderableDelayedDragStartListener(index: i, child: cartao)
            : cartao,
      );
    }

    const lateral = EdgeInsets.symmetric(horizontal: 16);
    if (controle.reordenavel) {
      return ReorderableListView.builder(
        key: const Key('lista-radar'),
        padding: lateral,
        buildDefaultDragHandles: false,
        header: topo,
        footer: rodape,
        itemCount: lista.length,
        itemBuilder: cartao,
        onReorderItem: (de, para) => unawaited(controle.reordenar(de, para)),
      );
    }
    return ListView.builder(
      key: const Key('lista-radar'),
      padding: lateral,
      itemCount: lista.length + 2,
      itemBuilder: (ctx, i) =>
          i == 0 ? topo : (i == lista.length + 1 ? rodape : cartao(ctx, i - 1)),
    );
  }
}
