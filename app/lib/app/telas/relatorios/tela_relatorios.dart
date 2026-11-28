// Tela Relatórios: o Relatório de Abertura de hoje (ou o mais recente) e a
// lista dos anteriores. No PC (>= 840) a lista fica numa coluna à direita; no
// celular, numa folha inferior aberta pelo botão "Anteriores". Sem conta, sem
// o escopo da pasta ou sem relatórios, a aba mostra só a mensagem.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../../nucleo/relatorios/filtros_relatorio.dart';
import '../../componentes/cartao.dart';
import '../../componentes/controles.dart';
import '../../componentes/carregando.dart';
import '../../estado/estado_app.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../../tema/layout.dart';
import 'controle_relatorios.dart';
import 'paleta_relatorio.dart';
import 'vista_relatorio.dart';

const textoHojeIndisponivel =
    'O relatório de hoje ainda não está disponível (fica pronto até 9h30 em '
    'dias de pregão)';
const textoRelatoriosSemConexao =
    'Sem conexão com o Google. Mostrando os relatórios salvos neste aparelho.';
const textoRelatoriosSemConexaoVazio =
    'Sem conexão. Os relatórios aparecem aqui quando houver internet.';
const textoRelatoriosNovoLogin =
    'Para ver os relatórios, entre de novo com o Google';
const textoRelatoriosSemConta =
    'Entre com a sua conta Google para ver os relatórios.';
const textoRelatoriosVazio =
    'Nenhum relatório encontrado na pasta "Calculadora DARF - Relatórios". '
    'Se o acesso acabou de ser liberado, toque em Atualizar.';

class TelaRelatorios extends StatelessWidget {
  const TelaRelatorios({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ControleRelatorios>(
      create: (c) =>
          ControleRelatorios(c.read<ServicosApp>(), c.read<EstadoApp>()),
      child: const _Corpo(),
    );
  }
}

class _Corpo extends StatelessWidget {
  const _Corpo();

  @override
  Widget build(BuildContext context) {
    final controle = context.watch<ControleRelatorios>();
    final email = context.select<EstadoApp, String?>((e) => e.conta.email);
    final visao = controle.visao;
    final topoErro = [
      if (controle.erro case final e?) _Faixa(e, icone: Icons.error_outline),
    ];
    final Widget conteudo;
    if (visao == null) {
      conteudo = const Carregando();
    } else {
      conteudo = switch (visao.situacao) {
        SituacaoRelatorios.novoLogin => _Mensagem(
          topo: topoErro,
          texto: textoRelatoriosNovoLogin,
          botao: email == null
              ? null
              : FilledButton(
                  onPressed: () => unawaited(controle.entrarDeNovo()),
                  child: const Text('Entrar de novo com o Google'),
                ),
          nota: 'A sincronização continua funcionando normalmente.',
        ),
        SituacaoRelatorios.semConta => _Mensagem(
          topo: topoErro,
          texto: textoRelatoriosSemConta,
          botao: FilledButton(
            onPressed: () => unawaited(controle.entrar()),
            child: const Text('Entrar com o Google'),
          ),
        ),
        SituacaoRelatorios.ok || SituacaoRelatorios.semConexao =>
          expandido(context)
              ? _Expandido(controle, visao)
              : _Compacto(controle, visao),
      };
    }
    final novo = context.select<EstadoApp, ResumoRelatorio?>(
      (e) => e.relatoriosNovos.firstOrNull,
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: novo == null
          ? conteudo
          : Column(
              children: [
                _FaixaNovoRelatorio(controle, novo),
                Expanded(child: conteudo),
              ],
            ),
    );
  }
}

/// Aviso de relatório novo no topo da aba: "Abrir" mostra o relatório e
/// "Dispensar" só some; os dois marcam como avisado.
class _FaixaNovoRelatorio extends StatelessWidget {
  const _FaixaNovoRelatorio(this.controle, this.novo);

  final ControleRelatorios controle;
  final ResumoRelatorio novo;

  @override
  Widget build(BuildContext context) {
    final margem = expandido(context) ? 24.0 : 12.0;
    final hora = horaDeGeracao(
      novo.geradoEm ??
          (controle.nomeAberto == novo.nome ? controle.aberto?.geradoEm : null),
    );
    final texto =
        'Novo relatório de abertura: ${dataPorExtenso(novo.data)}'
        '${hora == null ? '' : ', gerado às $hora'}';
    return Padding(
      key: const Key('faixa-novo-relatorio'),
      padding: EdgeInsets.fromLTRB(margem, 12, margem, 0),
      child: Cartao(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(texto, style: const TextStyle(fontWeight: FontWeight.bold)),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  children: [
                    TextButton(
                      key: const Key('dispensar-novo-relatorio'),
                      onPressed: () => unawaited(controle.dispensarNovo()),
                      child: const Text('Dispensar'),
                    ),
                    FilledButton(
                      key: const Key('abrir-novo-relatorio'),
                      onPressed: () => unawaited(controle.abrirNovo()),
                      child: const Text('Abrir'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- o relatório e as mensagens acima dele

/// O relatório aberto com os avisos da aba no topo; sem relatório, a
/// mensagem.
class _Principal extends StatelessWidget {
  const _Principal(this.controle, this.visao);

  final ControleRelatorios controle;
  final VisaoRelatorios visao;

  @override
  Widget build(BuildContext context) {
    final aberto = controle.aberto;
    final semConexao = visao.situacao == SituacaoRelatorios.semConexao;
    final topo = [
      if (semConexao)
        _Faixa(
          visao.itens.isEmpty
              ? textoRelatoriosSemConexaoVazio
              : textoRelatoriosSemConexao,
          icone: Icons.cloud_off,
        ),
      if (controle.erro case final e?) _Faixa(e, icone: Icons.error_outline),
      if (!visao.ehHoje && visao.itens.isNotEmpty && aberto != null)
        _HojeIndisponivel(controle.itemAberto?.data ?? aberto.data),
    ];
    if (visao.itens.isEmpty) {
      // sem conexão, a pasta pode não estar vazia: só a faixa
      return _Mensagem(
        topo: topo,
        texto: semConexao ? null : textoRelatoriosVazio,
      );
    }
    if (aberto == null) {
      // sem conexão, nada em cache para abrir: só as faixas
      return controle.erro == null && !semConexao
          ? const Carregando()
          : _Mensagem(topo: topo);
    }
    return VistaRelatorio(
      // outro relatório começa sem filtro
      key: ValueKey(controle.nomeAberto),
      relatorio: aberto,
      aoAbrirLink: controle.abrirLink,
      topo: topo,
      carteira: controle.carteira,
    );
  }
}

/// Pedido 2: a mensagem e, em destaque, a data do relatório à vista.
class _HojeIndisponivel extends StatelessWidget {
  const _HojeIndisponivel(this.data);

  final String data;

  @override
  Widget build(BuildContext context) {
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            textoHojeIndisponivel,
            style: TextStyle(color: CoresApp.de(context).textoSuave),
          ),
          Text(
            'Mostrando o relatório de ${dataPorExtenso(data)}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// Aviso discreto (sem conexão, falha ao abrir).
class _Faixa extends StatelessWidget {
  const _Faixa(this.texto, {required this.icone});

  final String texto;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        spacing: 8,
        children: [
          Icon(icone, size: 18, color: c.textoSuave),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: c.textoSuave, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mensagem no lugar do relatório, com o botão e a nota quando houver.
class _Mensagem extends StatelessWidget {
  const _Mensagem({this.topo = const [], this.texto, this.botao, this.nota});

  final List<Widget> topo;
  final String? texto;
  final Widget? botao;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final margem = expandido(context) ? 24.0 : 12.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(margem, 16, margem, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          ...topo,
          if (texto != null)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Cartao(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    spacing: 16,
                    children: [
                      Text(
                        texto!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15),
                      ),
                      ?botao,
                      if (nota != null)
                        Text(
                          nota!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textoSuave, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// --- a lista

class _BotaoAtualizar extends StatelessWidget {
  const _BotaoAtualizar(this.controle);

  final ControleRelatorios controle;

  @override
  Widget build(BuildContext context) => BotaoIcone(
    key: const Key('relatorios-atualizar'),
    tooltip: 'Atualizar',
    // ícone parado: a lista nunca espera a pasta
    onPressed: controle.atualizando
        ? null
        : () => unawaited(controle.atualizar()),
    icone: controle.atualizando ? Icons.hourglass_top : Icons.refresh,
  );
}

/// Data por extenso e a contagem do termômetro nas cores da leitura.
class _ItemRelatorio extends StatelessWidget {
  const _ItemRelatorio(
    this.item, {
    required this.aberto,
    required this.aoTocar,
  });

  final ResumoRelatorio item;
  final bool aberto;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = CoresApp.de(context);
    final t = item.termometro;
    return Padding(
      key: Key('item-relatorio-${item.data}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      // Material próprio: o fundo do item aberto fica sobre o cartão
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          selected: aberto,
          selectedColor: c.texto,
          selectedTileColor: c.navAtivo.withValues(alpha: .14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: aberto ? BorderSide(color: c.navAtivo) : BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            dataPorExtenso(item.data),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: t == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final l in Leitura.values)
                        SeloLeitura(l, texto: contagemLeitura(l, t.de(l))),
                    ],
                  ),
                ),
          onTap: aoTocar,
        ),
      ),
    );
  }
}

/// Lista preguiçosa dos relatórios: só os itens à vista são construídos.
ListView _lista(
  ControleRelatorios controle,
  VisaoRelatorios visao, {
  ScrollController? rolagem,
  EdgeInsetsGeometry? padding,
  void Function()? antes,
}) {
  final itens = filtrarPorPeriodo(
    visao.itens,
    controle.periodoDias,
    visao.hoje,
  );
  if (itens.isEmpty && controle.periodoDias != null) {
    return ListView(
      controller: rolagem,
      padding: padding,
      children: const [
        Padding(
          key: Key('periodo-vazio'),
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text('Nenhum relatório neste período'),
        ),
      ],
    );
  }
  return ListView.builder(
    controller: rolagem,
    padding: padding,
    itemCount: itens.length,
    itemBuilder: (_, n) {
      final i = itens[n];
      return _ItemRelatorio(
        i,
        aberto: i.nome == controle.nomeAberto,
        aoTocar: () {
          antes?.call();
          unawaited(controle.abrir(i.nome));
        },
      );
    },
  );
}

/// "7 dias", "30 dias", "90 dias" e "Todos" (padrão), pela data do arquivo.
class _ChipsPeriodo extends StatelessWidget {
  const _ChipsPeriodo(this.controle);

  final ControleRelatorios controle;

  @override
  Widget build(BuildContext context) => Segmentado<int?>(
    key: const Key('periodo-relatorios'),
    // compacto também no PC: na coluna da lista, com o ✓ os rótulos quebram
    // em duas linhas
    compacto: true,
    opcoes: const [
      (7, '7 dias'),
      (30, '30 dias'),
      (90, '90 dias'),
      (null, 'Todos'),
    ],
    valor: controle.periodoDias,
    aoMudar: controle.definirPeriodo,
    chaveOpcao: (dias) => Key('periodo-${dias ?? 'todos'}'),
  );
}

const _tituloLista = Text(
  'Relatórios anteriores',
  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
);

// --- expandido (PC): vista + coluna da lista

class _Expandido extends StatelessWidget {
  const _Expandido(this.controle, this.visao);

  final ControleRelatorios controle;
  final VisaoRelatorios visao;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _Principal(controle, visao)),
        SizedBox(
          key: const Key('lista-relatorios'),
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 24, 16),
            child: Cartao(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // o título numa linha só, com Atualizar à direita
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: _tituloLista),
                            _BotaoAtualizar(controle),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ChipsPeriodo(controle),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _lista(controle, visao)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- compacto (celular): vista em tela cheia + folha da lista

class _Compacto extends StatelessWidget {
  const _Compacto(this.controle, this.visao);

  final ControleRelatorios controle;
  final VisaoRelatorios visao;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              BotaoSecundario(
                onPressed: visao.itens.isEmpty
                    ? null
                    : () => unawaited(_abrirFolha(context)),
                icone: Icons.history,
                rotulo: 'Anteriores',
              ),
              const Spacer(),
              _BotaoAtualizar(controle),
            ],
          ),
        ),
        Expanded(child: _Principal(controle, visao)),
      ],
    );
  }

  Future<void> _abrirFolha(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (folha) => ChangeNotifierProvider<ControleRelatorios>.value(
      value: controle,
      child: Consumer<ControleRelatorios>(
        builder: (_, controle, _) {
          final visao = controle.visao ?? this.visao;
          // arrastar sobe a folha até 90% da tela; depois a lista rola
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .6,
            minChildSize: .3,
            maxChildSize: .9,
            builder: (_, rolagem) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [_tituloLista, _ChipsPeriodo(controle)],
                  ),
                ),
                Expanded(
                  child: _lista(
                    controle,
                    visao,
                    rolagem: rolagem,
                    padding: const EdgeInsets.only(bottom: 16),
                    antes: () => Navigator.of(folha).pop(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
