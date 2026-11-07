// Tela Notícias: topo com o status da busca, filtros e a chave de notificação, e
// as matérias do radar: no PC um mural de colunas com um destaque no topo; no
// celular uma lista de cartões (calculadora_darf.py:2083-2336; android/main.py:
// 1868-1997). A lista nunca espera a rede: a busca roda por baixo e a tela
// continua rolando.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../componentes/logo_ativo.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'cartao_noticia.dart';
import 'controle_noticias.dart';
import 'mural.dart';

class TelaNoticias extends StatelessWidget {
  const TelaNoticias({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleNoticias>(
      create: (c) =>
          ControleNoticias(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: const _Corpo(),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo();

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleNoticias>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: EscopoLogos(
        child: expandido(context)
            ? _Expandido(controle: controle)
            : _Compacto(controle: controle),
      ),
    );
  }
}

/// Status da busca; em vermelho quando houve falha.
class _Status extends StatelessWidget {
  const _Status(this.controle);

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        controle.status,
        key: const Key('status-noticias'),
        style: TextStyle(
          color: controle.statusErro ? c.queda : c.textoSuave,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Erro ao ler as notícias, com a lista anterior ainda à mão.
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

/// Todas / Relevantes.
class _Tema extends StatelessWidget {
  const _Tema(this.controle);

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) => BotaoSegmentado<String>(
    opcoes: const [
      (todasNoticias, todasNoticias),
      (relevantesNoticias, relevantesNoticias),
    ],
    valor: controle.tema,
    aoMudar: controle.definirTema,
  );
}

/// Menu do ativo, com o botão que tira o filtro.
class _FiltroAtivo extends StatelessWidget {
  const _FiltroAtivo(this.controle, {required this.rotulo});

  final ControleNoticias controle;

  /// Texto antes do ativo escolhido ("Ativo: " no celular).
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final alvo = expandido(context) ? 40.0 : 48.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          key: const Key('menu-ativo-noticias'),
          tooltip: 'Filtrar por ativo',
          initialValue: controle.ticker,
          onSelected: controle.definirTicker,
          itemBuilder: (_) => [
            for (final t in [todosAtivos, ...controle.ativos])
              PopupMenuItem(value: t, child: Text(t)),
          ],
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: c.bordaCampo),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: alvo),
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$rotulo${controle.ticker}',
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
        if (controle.filtrandoAtivo)
          IconButton(
            key: const Key('limpar-filtro-noticias'),
            tooltip: 'Mostrar todos os ativos',
            onPressed: () => controle.definirTicker(todosAtivos),
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }
}

/// "Notificar notícias relevantes" e a chave.
class _Notificar extends StatelessWidget {
  const _Notificar(this.controle, {required this.sub});

  final ControleNoticias controle;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Notificar notícias relevantes'),
                Text(sub, style: TextStyle(color: c.textoSuave, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            key: const Key('chave-notificar'),
            value: controle.notificar,
            onChanged: (v) => unawaited(controle.definirNotificar(v)),
          ),
        ],
      ),
    );
  }
}

const _textoRelevantes =
    'Relevantes: fato relevante, resultado, proventos, recomendação, '
    'fusão/aquisição, recompra, desdobramento, governança, jurídico e fortes '
    'oscilações. Clique na notícia para abrir.';

/// A lista vazia, ou o carregamento da primeira leitura.
class _Vazio extends StatelessWidget {
  const _Vazio(this.controle);

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) {
    final texto = controle.textoVazio(expandido: expandido(context));
    if (texto == null) return const Carregando();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(color: CoresApp.de(context).textoSuave),
        ),
      ),
    );
  }
}

// --- expandido (PC)

class _Expandido extends StatelessWidget {
  const _Expandido({required this.controle});

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                        const Text(
                          'Notícias do radar',
                          style: TextStyle(
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
                        _Tema(controle),
                        _FiltroAtivo(controle, rotulo: ''),
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(controle.atualizar(forcar: true)),
                          child: const Text('Atualizar'),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  spacing: 16,
                  children: [
                    SizedBox(width: 300, child: _Notificar(controle, sub: '')),
                    Expanded(
                      child: Text(
                        _textoRelevantes,
                        style: TextStyle(
                          color: CoresApp.de(context).textoSuave,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (controle.erro != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _Erro(controle.erro!),
          ),
        Expanded(child: _Mural(controle)),
      ],
    );
  }
}

/// Destaque no topo e o resto em colunas independentes, cada uma uma lista
/// preguiçosa: só os cartões à vista são construídos (e só eles pedem imagem).
class _Mural extends StatelessWidget {
  const _Mural(this.controle);

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) {
    final itens = controle.itens;
    if (itens.isEmpty) return _Vazio(controle);
    return LayoutBuilder(
      builder: (context, caixa) {
        final largura = caixa.maxWidth - 48;
        final ncol = colunasMural(largura);
        final detalhes = controle.visao?.detalhes ?? const {};
        final destaque = ncol >= 2 ? escolherDestaque(itens, detalhes) : null;
        final resto = [
          for (final i in itens)
            if (i.id != destaque?.id) i,
        ];
        final larguraColuna = (largura - espacoMural * (ncol - 1)) / ncol;
        // altura estimada de cada cartão, com o espaço entre eles
        final indices = {for (final (n, i) in resto.indexed) i.id: n};
        double altura(Noticia i) {
          final det = detalhes[i.id];
          final estilo = estiloNoticia(i, det, indices[i.id]!);
          return alturaNoticia(i, det, estilo, larguraColuna) + espacoMural;
        }

        final colunas = distribuirMural(resto, ncol, altura);
        return CustomScrollView(
          slivers: [
            if (destaque != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, espacoMural),
                sliver: SliverToBoxAdapter(
                  child: CartaoNoticia(
                    key: ValueKey('destaque-${destaque.id}'),
                    item: destaque,
                    estilo: EstiloNoticia.destaque,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              sliver: SliverCrossAxisGroup(
                slivers: [
                  for (final (c, itensColuna) in colunas.indexed)
                    SliverCrossAxisExpanded(
                      flex: 1,
                      sliver: SliverPadding(
                        padding: EdgeInsets.only(
                          left: c == 0 ? 0 : espacoMural / 2,
                          right: c == ncol - 1 ? 0 : espacoMural / 2,
                        ),
                        sliver: SliverList.separated(
                          itemCount: itensColuna.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: espacoMural),
                          itemBuilder: (_, n) {
                            final item = itensColuna[n];
                            return CartaoNoticia(
                              key: ValueKey(item.id),
                              item: item,
                              estilo: estiloNoticia(
                                item,
                                detalhes[item.id],
                                indices[item.id]!,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- compacto (celular)

class _Compacto extends StatelessWidget {
  const _Compacto({required this.controle});

  final ControleNoticias controle;

  @override
  Widget build(BuildContext context) {
    final itens = controle.itens;
    final vazio = controle.textoVazio(expandido: false);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Cartao(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Notícias do radar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Atualizar',
                        onPressed: () =>
                            unawaited(controle.atualizar(forcar: true)),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  _Status(controle),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Tema(controle),
                      _FiltroAtivo(controle, rotulo: 'Ativo: '),
                    ],
                  ),
                  _Notificar(
                    controle,
                    sub: 'Com o app aberto ou em segundo plano',
                  ),
                ],
              ),
            ),
          ),
        ),
        if (controle.erro != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: _Erro(controle.erro!)),
          ),
        if (itens.isEmpty)
          SliverToBoxAdapter(
            child: vazio == null
                ? const SizedBox(height: 120, child: Carregando())
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      vazio,
                      style: TextStyle(color: CoresApp.de(context).textoSuave),
                    ),
                  ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: itens.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, n) => CartaoNoticia(
                key: ValueKey(itens[n].id),
                item: itens[n],
                estilo: EstiloNoticia.texto,
                compacto: true,
              ),
            ),
          ),
      ],
    );
  }
}
