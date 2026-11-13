// Menu do botão direito da Apuração no PC: as ações da linha clicada (compra,
// venda ou ativo da Posição) e as gerais da tela. Cada item chama a ação que
// já existe nos botões; o que não se aplica (mês fechado, visão de amigo, sem
// quantidade restante) fica escondido.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../nucleo/nucleo.dart';
import '../../estado/estado_app.dart';
import '../../plataforma/plataforma.dart';
import '../../servicos/api.dart';
import '../../tema/cores_app.dart';
import '../grafico/tela_grafico.dart';
import '../metas/tela_metas.dart';
import 'controle_apuracao.dart';

/// A linha clicada: o ticker e o texto do cabeçalho do menu; [lote] numa
/// compra da carteira, [vendaId] numa venda.
class AlvoMenu {
  const AlvoMenu({
    required this.ticker,
    required this.cabecalho,
    this.lote,
    this.vendaId,
  });

  final String ticker;
  final String cabecalho;
  final Lote? lote;
  final String? vendaId;
}

enum _Acao {
  vender,
  comprarAtivo,
  editarCompra,
  excluirCompra,
  editarVenda,
  excluirVenda,
  criarMeta,
  verSugestao,
  grafico,
  radar,
  copiar,
  comprar,
  trocarMes,
  alternarLista,
  metas,
  fecharMes,
}

/// Contexto da tela da Apuração, para o menu: a linha clicada pode sumir
/// (a lista troca, os dados recarregam) enquanto o menu está aberto.
class ContextoMenuApuracao extends InheritedWidget {
  const ContextoMenuApuracao({
    super.key,
    required this.contexto,
    required super.child,
  });

  final BuildContext contexto;

  /// O contexto da tela; sem ela, o próprio [c].
  static BuildContext de(BuildContext c) =>
      c.getInheritedWidgetOfExactType<ContextoMenuApuracao>()?.contexto ?? c;

  @override
  bool updateShouldNotify(ContextoMenuApuracao antigo) => false;
}

/// Abre o menu em [posicao] (global, a do cursor). Sem [alvo], só as ações
/// gerais.
Future<void> abrirMenuApuracao(
  BuildContext c,
  Offset posicao, {
  AlvoMenu? alvo,
}) async {
  c = ContextoMenuApuracao.de(c);
  final controle = c.read<ControleApuracao>();
  // um clique direito por vez: o seguinte espera o menu anterior (e a
  // leitura do radar) terminar
  if (controle.menuAbrindo) return;
  controle.menuAbrindo = true;
  final estado = c.read<EstadoApp>();
  final amigo = estado.amigo != null;
  final t = alvo?.ticker;
  final overlay = Overlay.of(c).context.findRenderObject()! as RenderBox;
  final ponto = overlay.globalToLocal(posicao);
  // o radar decide entre "Adicionar ao Radar" e "Já está no Radar"
  final VisaoRadar? radar;
  try {
    radar = t == null || amigo ? null : await controle.meuRadar();
  } catch (_) {
    controle.menuAbrindo = false;
    rethrow;
  }
  if (!c.mounted) {
    controle.menuAbrindo = false;
    return;
  }
  final noRadar = radar?.itens.any((i) => i.ticker == t) ?? false;
  final nome = radar?.itens.where((i) => i.ticker == t).firstOrNull?.nome;

  final cores = CoresApp.de(c);
  final livre = !controle.gravando;
  final lotes = controle.visaoLotes;
  final podeLotes = !amigo && (lotes?.editavel ?? false);
  final podeVendas = !amigo && (controle.visao?.editavel ?? false);
  final emCarteira =
      t != null &&
      (lotes?.dados.lotes.any((l) => l.ticker == t && restante(l) > 0) ??
          false);
  final lote = alvo?.lote;
  final podeVender =
      podeLotes && (lote != null ? restante(lote) > 0 : emCarteira);
  final destino = controle.modoLista == ModoLista.carteira
      ? ModoLista.posicao
      : ModoLista.carteira;
  final visao = controle.visao;

  PopupMenuItem<_Acao> item(
    _Acao acao,
    IconData icone,
    String texto, {
    bool habilitado = true,
  }) => PopupMenuItem<_Acao>(
    value: acao,
    enabled: habilitado,
    height: 36,
    child: Row(
      spacing: 12,
      children: [
        Icon(icone, size: 18, color: cores.textoSuave),
        Text(texto),
      ],
    ),
  );
  PopupMenuItem<_Acao> titulo(String texto, {bool forte = false}) =>
      PopupMenuItem<_Acao>(
        enabled: false,
        height: forte ? 36 : 28,
        child: Text(
          texto,
          style: forte
              ? TextStyle(color: cores.texto, fontWeight: FontWeight.bold)
              : TextStyle(color: cores.textoSuave, fontSize: 11),
        ),
      );

  final itens = <PopupMenuEntry<_Acao>>[
    if (alvo != null && t != null) ...[
      titulo(alvo.cabecalho, forte: true),
      if (alvo.vendaId != null && podeVendas) ...[
        item(
          _Acao.editarVenda,
          Icons.edit_outlined,
          'Editar venda',
          habilitado: livre,
        ),
        item(
          _Acao.excluirVenda,
          Icons.delete_outline,
          'Excluir venda',
          habilitado: livre,
        ),
      ],
      if (podeVender)
        item(
          _Acao.vender,
          Icons.sell_outlined,
          'Registrar venda',
          habilitado: livre,
        ),
      if (podeLotes)
        item(
          _Acao.comprarAtivo,
          Icons.add_shopping_cart,
          'Nova compra de $t',
          habilitado: livre,
        ),
      if (lote != null && podeLotes) ...[
        item(
          _Acao.editarCompra,
          Icons.edit_outlined,
          'Editar compra',
          habilitado: livre,
        ),
        item(
          _Acao.excluirCompra,
          Icons.delete_outline,
          // o mesmo título do diálogo de excluir
          c.read<Plataforma>().windows ? 'Excluir ativo' : 'Excluir compra',
          habilitado: livre,
        ),
      ],
      const PopupMenuDivider(),
      if (!amigo && emCarteira)
        item(_Acao.criarMeta, Icons.flag_outlined, 'Criar meta de alvo e stop'),
      // fora da carteira e do Radar, o ativo não aparece nas sugestões
      if (!amigo && (emCarteira || noRadar))
        item(
          _Acao.verSugestao,
          Icons.lightbulb_outline,
          'Ver sugestão de saída',
        ),
      item(_Acao.grafico, Icons.show_chart, 'Ver gráfico'),
      if (!amigo)
        noRadar
            ? item(
                _Acao.radar,
                Icons.radar,
                'Já está no Radar',
                habilitado: false,
              )
            : item(_Acao.radar, Icons.radar, 'Adicionar ao Radar'),
      item(_Acao.copiar, Icons.content_copy, 'Copiar ticker'),
      const PopupMenuDivider(),
      titulo('Geral'),
    ],
    if (podeLotes)
      item(_Acao.comprar, Icons.add, 'Nova compra', habilitado: livre),
    item(_Acao.trocarMes, Icons.calendar_month_outlined, 'Trocar mês…'),
    item(
      _Acao.alternarLista,
      Icons.swap_horiz,
      destino == ModoLista.posicao
          ? 'Posição em ${fmtData(controle.dataCorte)}'
          : 'Carteira atual',
    ),
    item(_Acao.metas, Icons.track_changes, 'Meta de lucro…'),
    if (controle.podeFechar && visao != null)
      item(
        _Acao.fecharMes,
        Icons.lock_outline,
        'Fechar mês ${fmtMes(visao.mes)}',
      ),
  ];

  final _Acao? acao;
  try {
    acao = await showMenu<_Acao>(
      context: c,
      position: RelativeRect.fromRect(
        Rect.fromPoints(ponto, ponto),
        Offset.zero & overlay.size,
      ),
      items: itens,
    );
  } finally {
    controle.menuAbrindo = false;
  }
  if (acao == null || !c.mounted) return;

  void comprarAtivo() => unawaited(controle.novaCompra(c, ticker: t));
  void vender() => unawaited(
    lote != null
        ? controle.registrarVenda(c, lote: lote)
        : controle.registrarVenda(c, ticker: t),
  );
  switch (acao) {
    case _Acao.vender:
      vender();
    case _Acao.comprarAtivo:
      comprarAtivo();
    case _Acao.editarCompra:
      unawaited(controle.editarLote(c, id: lote!.id));
    case _Acao.excluirCompra:
      unawaited(controle.excluirLote(c, id: lote!.id));
    case _Acao.editarVenda:
      unawaited(controle.editarVenda(c, id: alvo!.vendaId));
    case _Acao.excluirVenda:
      unawaited(controle.excluirVenda(c, id: alvo!.vendaId));
    case _Acao.criarMeta:
      unawaited(abrirMetas(c, ticker: t, compras: true));
    case _Acao.verSugestao:
      unawaited(abrirMetas(c, ticker: t));
    case _Acao.grafico:
      unawaited(
        abrirGrafico(
          c,
          ticker: t!,
          nome: nome ?? '',
          amigo: amigo,
          aoComprar: podeLotes ? comprarAtivo : null,
          aoVender: podeVender ? vender : null,
          aoVerNoticias: () => estado.verNoticias(t),
        ),
      );
    case _Acao.radar:
      unawaited(controle.adicionarRadar(c, t!));
    case _Acao.copiar:
      String aviso;
      try {
        await c.read<Plataforma>().copiarTexto(t!);
        aviso = '$t copiado';
      } catch (_) {
        aviso = 'Não foi possível copiar $t.';
      }
      if (c.mounted) {
        ScaffoldMessenger.maybeOf(c)
            ?.showSnackBar(SnackBar(content: Text(aviso)));
      }
    case _Acao.comprar:
      unawaited(controle.novaCompra(c));
    case _Acao.trocarMes:
      unawaited(controle.escolher(c));
    case _Acao.alternarLista:
      controle.escolherModo(destino);
    case _Acao.metas:
      unawaited(abrirMetas(c));
    case _Acao.fecharMes:
      unawaited(controle.fecharMes(c));
  }
}
