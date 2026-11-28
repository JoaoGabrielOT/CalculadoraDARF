// Tela de Apuração: barra (Mês, selo, Fechar mês),
// indicadores e Detalhamento (calculadora_darf.py:1279-1345, 1408-1443;
// android/main.py:725-866). As tabelas de compras e vendas entram em [conteudo]
// ([listasApuracao], Tarefa 14). Expandido: conteúdo e Detalhamento lado a lado; compacto: lista
// rolável com FAB.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart' show Cartao;
import '../../componentes/carregando.dart';
import '../../componentes/controles.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'controle_apuracao.dart';
import 'detalhamento.dart';
import 'indicadores.dart';
import 'lista_posicoes.dart';
import 'lista_vendas.dart';
import 'menu_contexto.dart';

class TelaApuracao extends StatelessWidget {
  /// [aoAbrirMetas] abre o diálogo de metas (cartão do celular);
  /// [conteudo] é a área das tabelas, que lê o [ControleApuracao] do contexto.
  const TelaApuracao({
    super.key,
    this.aoAbrirMetas,
    this.conteudo,
    this.sliversCompactos,
  }) : assert(
         conteudo == null || sliversCompactos != null,
         'TelaApuracao: o celular só mostra [conteudo] por [sliversCompactos].',
       );

  final VoidCallback? aoAbrirMetas;
  final WidgetBuilder? conteudo;

  /// Conteúdo do celular como slivers (listas lazy); sem ele o celular usa
  /// [conteudo] numa caixa só. Obrigatório quando há [conteudo].
  final List<Widget> Function(BuildContext)? sliversCompactos;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleApuracao>(
      create: (c) =>
          ControleApuracao(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: _Corpo(
        aoAbrirMetas: aoAbrirMetas,
        conteudo: conteudo,
        sliversCompactos: sliversCompactos,
      ),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo({
    required this.aoAbrirMetas,
    required this.conteudo,
    required this.sliversCompactos,
  });

  final VoidCallback? aoAbrirMetas;
  final WidgetBuilder? conteudo;
  final List<Widget> Function(BuildContext)? sliversCompactos;

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleApuracao>();
    final grande = expandido(context);
    final visao = controle.visao;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: !grande && visao != null && visao.editavel
          ? FloatingActionButton(
              tooltip: 'Nova compra',
              onPressed: controle.gravando
                  ? null
                  : () => controle.novaCompra(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: grande
          ? _Expandido(controle: controle, conteudo: conteudo)
          : _Compacto(
              controle: controle,
              aoAbrirMetas: aoAbrirMetas,
              conteudo: conteudo,
              slivers: sliversCompactos,
            ),
    );
  }
}

class _Expandido extends StatelessWidget {
  const _Expandido({required this.controle, required this.conteudo});

  final ControleApuracao controle;
  final WidgetBuilder? conteudo;

  @override
  Widget build(BuildContext context) {
    final visao = controle.visao;
    // botão direito fora das linhas: só as ações gerais
    return ContextoMenuApuracao(
      contexto: context,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) =>
            unawaited(abrirMenuApuracao(context, d.globalPosition)),
        child: Column(
          children: [
            _Progresso(controle.carregando || controle.verificando),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: _Barra(controle: controle, compacto: false),
            ),
            _Avisos(controle),
            if (visao == null)
              Expanded(
                child: controle.erro == null
                    ? const Carregando()
                    : const SizedBox.shrink(),
              )
            else
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      Indicadores(
                        apuracao: visao.apuracao,
                        mes: visao.mes,
                        compacto: false,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child:
                                  conteudo?.call(context) ?? const SizedBox(),
                            ),
                            const SizedBox(width: 16),
                            Detalhamento(
                              apuracao: visao.apuracao,
                              mes: visao.mes,
                              compacto: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Compacto extends StatelessWidget {
  const _Compacto({
    required this.controle,
    required this.aoAbrirMetas,
    required this.conteudo,
    required this.slivers,
  });

  final ControleApuracao controle;
  final VoidCallback? aoAbrirMetas;
  final WidgetBuilder? conteudo;
  final List<Widget> Function(BuildContext)? slivers;

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    final visao = controle.visao;
    final ativas = estado.metasAtivas;
    final listas = visao == null ? null : slivers?.call(context);
    final topo = <Widget>[
      _Progresso(controle.carregando || controle.verificando),
      const SizedBox(height: 12),
      _Barra(controle: controle, compacto: true),
      _Avisos(controle),
      if (estado.amigo == null) ...[
        const SizedBox(height: 12),
        _CartaoLink(
          icone: Icons.account_balance_wallet,
          texto: controle.textoSaldo ?? 'Definir saldo em conta',
          aoTocar: () => estado.irPara(Aba.caixa),
        ),
        const SizedBox(height: 12),
        _CartaoLink(
          icone: Icons.track_changes,
          texto:
              'Meta de lucro / Preço-alvo'
              '${ativas > 0 ? ' · $ativas ativa${ativas != 1 ? 's' : ''}' : ''}',
          aoTocar: aoAbrirMetas,
        ),
      ],
      if (visao == null && controle.erro == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Carregando(),
        )
      else if (visao != null) ...[
        const SizedBox(height: 12),
        Indicadores(apuracao: visao.apuracao, mes: visao.mes, compacto: true),
        const SizedBox(height: 12),
        CartoesRegime(apuracao: visao.apuracao),
        const SizedBox(height: 12),
        Detalhamento(apuracao: visao.apuracao, mes: visao.mes, compacto: true),
        if (conteudo != null && listas == null) ...[
          const SizedBox(height: 12),
          conteudo!(context),
        ],
      ],
    ];
    // CustomScrollView: as listas são slivers e só montam os cartões à vista.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverList(delegate: SliverChildListDelegate(topo)),
        ),
        if (listas != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            sliver: SliverMainAxisGroup(slivers: listas),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
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

/// Erro de leitura do mês ou da carga, com o seletor de mês ainda à mão; sem
/// erro, o aviso de saldo inconsistente do custo médio.
class _Avisos extends StatelessWidget {
  const _Avisos(this.controle);

  final ControleApuracao controle;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    if (controle.verificando) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Text(
            'Verificando as metas antes de fechar…',
            style: TextStyle(color: c.textoSuave),
          ),
        ),
      );
    }
    final inconsistentes = controle.visao?.apuracao.inconsistentes ?? const [];
    final texto =
        controle.erro ??
        controle.visao?.erroLeitura ??
        (inconsistentes.isEmpty
            ? null
            : avisosSaldoInconsistente(inconsistentes));
    if (texto == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
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

/// Barra da tela (py:1279-1295; o seletor de dados fica na casca): ◂ mês ▸ e
/// o selo à esquerda; Fechar mês na ponta direita (PC) ou no menu (celular).
class _Barra extends StatelessWidget {
  const _Barra({required this.controle, required this.compacto});

  final ControleApuracao controle;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final estado = context.watch<EstadoApp>();
    final visao = controle.visao;
    final pode = controle.podeFechar;
    final mes = SeletorMes(
      mes: estado.mes,
      maximo: ambiente.hoje().substring(0, 7),
      aoMudar: estado.trocarMes,
      aoAbrir: () => controle.escolher(context),
    );
    final selo = visao == null ? null : _Selo(visao);
    final inicio = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [mes, ?selo],
    );
    return Row(
      spacing: 8,
      children: [
        if (compacto)
          // abaixo de 360 px, o mês e o selo encolhem em vez de estourar
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: inicio,
            ),
          )
        else ...[
          inicio,
          const Spacer(),
        ],
        if (!compacto)
          BotaoPrincipal(
            icone: Icons.lock,
            rotulo: 'Fechar mês',
            onPressed: pode ? () => controle.fecharMes(context) : null,
          )
        else if (visao != null && visao.editavel)
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            enabled: pode,
            onSelected: (_) => controle.fecharMes(context),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'fechar', child: Text('Fechar mês')),
            ],
          ),
      ],
    );
  }
}

/// "● Aberto", "Fechado" ou "Somente leitura" (py:1521-1530).
class _Selo extends StatelessWidget {
  const _Selo(this.visao);

  final VisaoMes visao;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    if (visao.somenteLeitura) {
      return Selo(texto: 'Somente leitura', cor: c.aviso);
    }
    if (visao.dados.fechado) return Selo(texto: 'Fechado', cor: c.textoSuave);
    return Selo(texto: 'Aberto', cor: c.alta, ponto: true);
  }
}

/// Cartão que leva a outra tela (saldo, metas), como no Android.
class _CartaoLink extends StatelessWidget {
  const _CartaoLink({
    required this.icone,
    required this.texto,
    required this.aoTocar,
  });

  final IconData icone;
  final String texto;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final cartao = Cartao(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        spacing: 8,
        children: [
          Icon(icone, size: 18, color: c.textoSuave),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (aoTocar != null)
            Icon(Icons.chevron_right, size: 18, color: c.textoSuave),
        ],
      ),
    );
    // sem ação (diálogo de metas ainda não ligado) não parece tocável
    if (aoTocar == null) return cartao;
    return InkWell(
      borderRadius: BorderRadius.circular(c.raioCartao),
      onTap: aoTocar,
      child: cartao,
    );
  }
}

/// Ativos comprados e Vendas do mês, para o parâmetro `conteudo`. Expandido:
/// os dois cartões numa lista rolável (estreita, só as tabelas rolam na
/// horizontal: [RolagemTabela]); compacto: cartões (a rolagem é da tela).
Widget listasApuracao(BuildContext c) => ListView(
  children: const [ListaAtivos(), SizedBox(height: 16), ListaVendas()],
);

/// Conteúdo do celular: cartões das compras e vendas, montados sob demanda.
List<Widget> listasSliversApuracao(BuildContext c) => const [
  ListaAtivos(sliver: true),
  SliverToBoxAdapter(child: SizedBox(height: 24)),
  ListaVendas(sliver: true),
];
