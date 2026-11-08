// Tela de Apuração: barra (Visualizando, Atualizar, Mês, selo, Fechar mês),
// indicadores e Detalhamento (calculadora_darf.py:1279-1345, 1408-1443;
// android/main.py:725-866). As tabelas de compras e vendas entram em [conteudo]
// ([listasApuracao], Tarefa 14). Expandido: conteúdo e Detalhamento lado a lado; compacto: lista
// rolável com FAB.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../componentes/cartao.dart';
import '../../componentes/carregando.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'controle_apuracao.dart';
import 'detalhamento.dart';
import 'indicadores.dart';
import 'lista_posicoes.dart';
import 'lista_vendas.dart';
import 'seletor_visao.dart';

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
    return Column(
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
                          child: conteudo?.call(context) ?? const SizedBox(),
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
      const SizedBox(height: 12),
      const SeletorVisao(largura: double.infinity),
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

/// Barra da tela. Expandido: Visualizando + Atualizar à esquerda, Mês, selo e
/// Fechar mês à direita (py:1279-1295). Compacto: mês, selo e menu.
class _Barra extends StatelessWidget {
  const _Barra({required this.controle, required this.compacto});

  final ControleApuracao controle;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final estado = context.watch<EstadoApp>();
    final visao = controle.visao;
    final pode =
        visao != null &&
        visao.editavel &&
        !controle.carregando &&
        !controle.fechando;
    final botaoMes = OutlinedButton(
      onPressed: () => controle.escolher(context),
      child: Text('${fmtMes(estado.mes)}  ▾'),
    );
    final selo = visao == null ? null : _Selo(visao);
    if (compacto) {
      return Row(
        spacing: 8,
        children: [
          botaoMes,
          ?selo,
          const Spacer(),
          if (estado.amigo != null)
            IconButton(
              tooltip: 'Atualizar',
              icon: const Icon(Icons.refresh),
              onPressed: estado.carregandoAmigo
                  ? null
                  : () => controle.atualizarAmigo(),
            ),
          if (visao != null && visao.editavel)
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
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Visualizando',
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SeletorVisao(),
        OutlinedButton(
          onPressed: estado.amigo == null || estado.carregandoAmigo
              ? null
              : controle.atualizarAmigo,
          child: const Text('Atualizar'),
        ),
        const SizedBox(width: 24),
        Text(
          'Mês',
          style: TextStyle(
            color: c.textoSuave,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        botaoMes,
        ?selo,
        FilledButton(
          onPressed: pode ? () => controle.fecharMes(context) : null,
          child: const Text('Fechar mês'),
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
      return Pilula(texto: 'Somente leitura', cor: c.aviso);
    }
    if (visao.dados.fechado) return const Pilula(texto: 'Fechado');
    return Pilula(texto: '● Aberto', fundo: c.seloAltaFundo, cor: c.alta);
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
/// duas tabelas numa lista rolável (com menos de [larguraMinimaListas] px, as
/// colunas não se espremem: a área rola na horizontal); compacto: cartões (a
/// rolagem é da tela).
const larguraMinimaListas = 1200.0;

Widget listasApuracao(BuildContext c) {
  const lotes = ListaAtivos();
  const vendas = ListaVendas();
  return LayoutBuilder(
    builder: (context, caixa) {
      final lista = ListView(
        children: const [lotes, SizedBox(height: 16), vendas],
      );
      if (caixa.maxWidth >= larguraMinimaListas) return lista;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: larguraMinimaListas,
          height: caixa.maxHeight,
          child: lista,
        ),
      );
    },
  );
}

/// Conteúdo do celular: cartões das compras e vendas, montados sob demanda.
List<Widget> listasSliversApuracao(BuildContext c) => const [
  ListaAtivos(sliver: true),
  SliverToBoxAdapter(child: SizedBox(height: 24)),
  ListaVendas(sliver: true),
];
