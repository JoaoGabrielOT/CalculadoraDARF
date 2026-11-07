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
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import '../../tema/temas.dart';
import '../apuracao/seletor_visao.dart';
import 'controle_radar.dart';
import 'linha_radar.dart';

/// Abre o gráfico do ativo (Tarefa 17); sem ele, tocar na linha não faz nada.
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
  return AcoesRadar(
    aoAbrir: () => abrir?.call(
      c,
      ticker: t,
      nome: item.nome.isNotEmpty ? item.nome : (dados?.nome ?? ''),
      dados: dados,
      amigo: amigo,
      jaTenho: meus.contains(t),
    ),
    aoComprar: amigo ? null : () => unawaited(controle.comprar(c, t)),
    aoVender: amigo || !(visao?.custodia.contains(t) ?? false)
        ? null
        : () => unawaited(controle.vender(c, t)),
    aoRemover: amigo ? null : () => unawaited(controle.remover(c, t)),
    aoImportar: amigo && !meus.contains(t)
        ? () => unawaited(controle.importar(c, t))
        : null,
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

/// "RISCO PELO ATR%" e as quatro faixas (py:2007-2012).
class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            'RISCO PELO ATR%',
            style: TextStyle(
              color: c.textoSuave,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final (i, atr) in _atrDaFaixa.indexed)
          () {
            final risco = classificarRisco(atr);
            return SeloRisco(
              risco,
              texto: '${risco.rotulo} · ${_faixasRotulo[i]}',
            );
          }(),
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
    final c = CoresApp.de(context);
    final (altas, quedas, media) = controle.resumo;
    final rotuloOrdem = ordensRadar
        .firstWhere(
          (o) => o.$1 == controle.ordem,
          orElse: () => ordensRadar.first,
        )
        .$2;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BotaoSegmentado<String>(
          opcoes: [for (final f in filtrosRadar) (f, f)],
          valor: controle.filtro,
          aoMudar: controle.definirFiltro,
        ),
        PopupMenuButton<String>(
          key: const Key('menu-ordem'),
          tooltip: 'Ordenar',
          initialValue: controle.ordem,
          onSelected: (k) => unawaited(controle.definirOrdem(k)),
          itemBuilder: (_) => [
            for (final (chave, rotulo) in ordensRadar)
              PopupMenuItem(value: chave, child: Text(rotulo)),
          ],
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.bordaCampo),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: expandido(context) ? 40 : 48,
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ordenar: $rotuloOrdem',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (media != null)
          Text(
            'Hoje: $altas em alta · $quedas em queda · média ${fmtPct(media)}',
            key: const Key('resumo-dia'),
            style: TextStyle(
              color: corVariacao(context, media),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
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
    final campo = TextField(
      key: const Key('campo-ticker'),
      controller: _campo,
      textCapitalization: TextCapitalization.characters,
      onSubmitted: (_) => unawaited(_enviar()),
      decoration: widget.compacto
          ? const InputDecoration(
              labelText: 'Adicionar ticker',
              hintText: 'Ex.: VALE3',
              isDense: true,
            )
          : const InputDecoration(
              hintText: 'Ticker (ex.: VALE3)',
              isDense: true,
            ),
    );
    if (widget.compacto) {
      return Row(
        spacing: 8,
        children: [
          Expanded(child: campo),
          IconButton(
            onPressed: () => unawaited(_enviar()),
            icon: Icon(
              Icons.add_circle,
              color: CoresApp.de(context).alta,
              size: 32,
            ),
            tooltip: 'Adicionar',
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        SizedBox(width: 200, child: campo),
        FilledButton(
          onPressed: () => unawaited(_enviar()),
          child: const Text('+  Adicionar'),
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
      return FilledButton(
        onPressed: () => unawaited(controle.importarTodos(context)),
        child: const Text('+  Importar todos para o meu radar'),
      );
    }
    final faltam = controle.novosDoAmigo.length;
    return FilledButton.icon(
      onPressed: faltam == 0
          ? null
          : () => unawaited(controle.importarTodos(context)),
      icon: const Icon(Icons.playlist_add),
      label: Text(
        faltam == 0
            ? 'Todos já estão no seu radar'
            : 'Importar $faltam para o meu radar',
      ),
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
                        const SeletorVisao(largura: 240),
                        if (amigo == null)
                          _Adicionar(controle: controle, compacto: false)
                        else
                          _ImportarTodos(controle: controle, compacto: false),
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(controle.atualizar(forcar: true)),
                          child: const Text('Atualizar'),
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
                    IconButton(
                      onPressed: () =>
                          unawaited(controle.atualizar(forcar: true)),
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Atualizar',
                    ),
                  ],
                ),
                _Status(controle),
                const SeletorVisao(largura: double.infinity),
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
