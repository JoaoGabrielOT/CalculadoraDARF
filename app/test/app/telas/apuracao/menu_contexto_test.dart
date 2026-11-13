// Menu do botão direito da Apuração no PC: itens por tipo de linha, o que
// some sem permissão de gravar e a ação de cada item.

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/apuracao/controle_apuracao.dart';
import 'package:calculadoradarf/app/telas/apuracao/tela_apuracao.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/abrir_formulario.dart' show campoTexto;
import '../../apoio/dados_exemplo.dart';
import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 1400);

Future<(ServicosFalsos, PlataformaFalsa)> _montar(
  WidgetTester t, {
  ServicosFalsos? servicos,
  Size tamanho = _pc,
  PlataformaFalsa? plataforma,
}) async {
  final s = servicos ?? ServicosFalsos();
  final p = plataforma ?? PlataformaFalsa();
  await montarApp(
    t,
    servicos: s,
    plataforma: p,
    tamanho: tamanho,
    tela: const TelaApuracao(
      conteudo: listasApuracao,
      sliversCompactos: listasSliversApuracao,
    ),
  );
  await t.pumpAndSettle();
  return (s, p);
}

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(TelaApuracao)), listen: false);

Future<void> _direito(WidgetTester t, Finder f) async {
  await t.tap(f, buttons: kSecondaryButton);
  await t.pumpAndSettle();
}

Finder _linha(String id) => find.byKey(Key('linha-$id'));

Finder _item(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
);

Future<void> _escolher(WidgetTester t, String texto) async {
  await t.tap(_item(texto));
  await t.pumpAndSettle();
}

Finder _noDialogo(String texto) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(texto));

const _doAtivo = [
  'Criar meta de alvo e stop',
  'Ver sugestão de saída',
  'Ver gráfico',
  'Copiar ticker',
];

const _geralSemGravar = ['Trocar mês…', 'Meta de lucro…'];

void _esperaItens(List<String> sim, [List<String> nao = const []]) {
  for (final x in sim) {
    expect(_item(x), findsOneWidget, reason: 'deveria ter "$x"');
  }
  for (final x in nao) {
    expect(_item(x), findsNothing, reason: 'não deveria ter "$x"');
  }
}

/// Sugestões com PETR4 em carteira, para o foco do menu.
VisaoSugestoes _sugestoes() => VisaoSugestoes(
  ativos: [
    SugestaoAtivo(
      ticker: 'PETR4',
      estado: EstadoDados.ok,
      barras: const [],
      posicao: PosicaoAtivo(
        ticker: 'PETR4',
        tipo: 'Ação',
        qtd: 60,
        custoGerencial: 1950,
        compras: [
          CompraNaPosicao(
            loteId: 'L1',
            mes: '2026-10',
            dataCompra: '2026-10-05',
            qtdOriginal: 100,
            restante: 60,
            preco: 32.5,
          ),
        ],
      ),
    ),
  ],
  rodape: const [],
);

class _PlataformaSemCopia extends PlataformaFalsa {
  @override
  Future<void> copiarTexto(String texto) async =>
      throw Exception('sem área de transferência');
}

void main() {
  setUp(() => ambiente = Ambiente.fixo(hoje: hojeExemplo));

  group('itens', () {
    testWidgets('compra: cabeçalho, ações da compra, do ativo e Geral; o '
        'clique direito marca a linha', (t) async {
      await _montar(t);
      await _direito(t, _linha('L1'));
      expect(find.text('PETR4 · 100 un. · ${brl(32.5)}'), findsOneWidget);
      _esperaItens(
        [
          'Registrar venda',
          'Nova compra de PETR4',
          'Editar compra',
          'Excluir ativo',
          ..._doAtivo,
          'Já está no Radar',
          'Geral',
          'Nova compra',
          ..._geralSemGravar,
          'Posição em 28/10/2026',
          'Fechar mês 10/2026',
        ],
        ['Adicionar ao Radar', 'Editar venda', 'Carteira atual'],
      );
      expect(
        t.widget<PopupMenuItem<Object?>>(_item('Já está no Radar')).enabled,
        isFalse,
      );
      // a linha ficou marcada
      expect(t.widget<Semantics>(_linha('L1')).properties.selected, isTrue);
    });

    testWidgets('compra fora do Radar oferece "Adicionar ao Radar"', (t) async {
      await _montar(t);
      await _direito(t, _linha('L2'));
      _esperaItens(['Adicionar ao Radar'], ['Já está no Radar']);
    });

    testWidgets('compra sem quantidade restante não oferece Registrar '
        'venda', (t) async {
      final s = ServicosFalsos();
      s.visoes['2026-10'] = visaoExemplo(
        Mes(
          mes: '2026-10',
          lotes: [
            Lote(
              id: 'L9',
              ticker: 'ITUB4',
              tipo: 'Ação',
              dataCompra: '2026-10-02',
              qtd: 10,
              preco: 30,
              vendas: [Venda(id: 'V9', data: '2026-10-03', qtd: 10, preco: 31)],
            ),
          ],
        ),
      );
      await _montar(t, servicos: s);
      await _direito(t, _linha('L9'));
      _esperaItens(
        ['Nova compra de ITUB4', 'Editar compra', 'Excluir ativo'],
        [
          'Registrar venda',
          'Criar meta de alvo e stop',
          // sem posição e fora do Radar, o foco não teria o que mostrar
          'Ver sugestão de saída',
        ],
      );
    });

    testWidgets('venda: Editar e Excluir venda, o ativo e Geral, sem as '
        'ações da compra', (t) async {
      await _montar(t);
      await _direito(t, _linha('V1'));
      _esperaItens(
        [
          'Editar venda',
          'Excluir venda',
          'Registrar venda',
          'Nova compra de PETR4',
          ..._doAtivo,
          'Nova compra',
          ..._geralSemGravar,
          'Fechar mês 10/2026',
        ],
        ['Editar compra', 'Excluir ativo'],
      );
    });

    testWidgets('ativo da Posição: o ativo e Geral, sem editar compra', (
      t,
    ) async {
      await _montar(t);
      await t.tap(find.text('Posição em 28/10/2026'));
      await t.pumpAndSettle();
      await _direito(t, find.byKey(const Key('ativo-PETR4')));
      _esperaItens(
        [
          'Registrar venda',
          'Nova compra de PETR4',
          ..._doAtivo,
          'Carteira atual',
          'Fechar mês 10/2026',
        ],
        ['Editar compra', 'Excluir ativo', 'Editar venda'],
      );
    });

    testWidgets('área vazia: só Geral', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      _esperaItens(
        [
          'Nova compra',
          ..._geralSemGravar,
          'Posição em 28/10/2026',
          'Fechar mês 10/2026',
        ],
        [..._doAtivo, 'Registrar venda', 'Geral'],
      );
    });

    testWidgets('visão de amigo esconde tudo que grava', (t) async {
      final (s, _) = await _montar(t);
      await _estado(t).trocarVisao('ana@exemplo.com');
      await t.pumpAndSettle();
      await _direito(t, _linha('L1'));
      _esperaItens(
        ['Ver gráfico', 'Copiar ticker', ..._geralSemGravar],
        [
          'Registrar venda',
          'Nova compra de PETR4',
          'Editar compra',
          'Excluir ativo',
          'Criar meta de alvo e stop',
          'Ver sugestão de saída',
          'Adicionar ao Radar',
          'Já está no Radar',
          'Nova compra',
          'Fechar mês 10/2026',
        ],
      );
      expect(s.chamadas.where((c) => c.startsWith('radar(')), isEmpty);
    });

    testWidgets('mês fechado esconde editar e excluir venda e Fechar mês', (
      t,
    ) async {
      await _montar(t);
      _estado(t).trocarMes('2026-09');
      await t.pumpAndSettle();
      await _direito(t, _linha('FV1'));
      _esperaItens(
        ['Ver gráfico', 'Copiar ticker', ..._geralSemGravar],
        [
          'Editar venda',
          'Excluir venda',
          'Registrar venda',
          'Nova compra de ITUB4',
          'Nova compra',
          'Fechar mês 09/2026',
        ],
      );
    });

    testWidgets('Esc fecha o menu', (t) async {
      await _montar(t);
      await _direito(t, _linha('L1'));
      expect(_item('Copiar ticker'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_item('Copiar ticker'), findsNothing);
    });

    testWidgets('celular: o botão direito não abre menu', (t) async {
      await _montar(t, tamanho: const Size(360, 3000));
      await _direito(t, find.byKey(const Key('cartao-lote-L1')));
      expect(_item('Copiar ticker'), findsNothing);
      expect(_item('Trocar mês…'), findsNothing);
    });
  });

  group('ações', () {
    testWidgets('Registrar venda abre a venda da compra', (t) async {
      await _montar(t);
      await _direito(t, _linha('L1'));
      await _escolher(t, 'Registrar venda');
      expect(_noDialogo('Registrar venda'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, 'PETR4');
    });

    testWidgets('Registrar venda pela venda usa o ticker dela', (t) async {
      await _montar(t);
      await _direito(t, _linha('V1'));
      await _escolher(t, 'Registrar venda');
      expect(_noDialogo('Registrar venda'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, 'PETR4');
    });

    testWidgets('Nova compra do ativo vem com o ticker', (t) async {
      await _montar(t);
      await _direito(t, _linha('L2'));
      await _escolher(t, 'Nova compra de VALE3');
      expect(_noDialogo('Novo ativo'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, 'VALE3');
    });

    testWidgets('Nova compra (Geral) vem em branco', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Nova compra');
      expect(_noDialogo('Novo ativo'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, '');
    });

    testWidgets('Editar compra abre a compra da linha', (t) async {
      await _montar(t);
      await _direito(t, _linha('L2'));
      await _escolher(t, 'Editar compra');
      expect(_noDialogo('Editar compra'), findsOneWidget);
      expect(campoTexto(t, 'ticker').controller!.text, 'VALE3');
    });

    testWidgets('Excluir ativo pergunta pela compra da linha', (t) async {
      await _montar(t);
      await _direito(t, _linha('L2'));
      await _escolher(t, 'Excluir ativo');
      expect(find.text('Excluir VALE3?'), findsOneWidget);
    });

    testWidgets('Editar venda abre a venda da linha', (t) async {
      await _montar(t);
      await _direito(t, _linha('V1'));
      await _escolher(t, 'Editar venda');
      expect(_noDialogo('Editar venda'), findsOneWidget);
    });

    testWidgets('Excluir venda pergunta e exclui a venda da linha', (t) async {
      final (s, _) = await _montar(t);
      await _direito(t, _linha('V1'));
      await _escolher(t, 'Excluir venda');
      expect(find.text('Excluir esta venda?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('excluirVenda(2026-10, V1)'));
    });

    for (final (rotulo, compras) in [
      ('Criar meta de alvo e stop', true),
      ('Ver sugestão de saída', false),
    ]) {
      testWidgets('$rotulo abre as Sugestões no cartão do ticker', (t) async {
        final s = ServicosFalsos()..visaoSugestoes = _sugestoes();
        await _montar(t, servicos: s);
        await _direito(t, _linha('L1'));
        await _escolher(t, rotulo);
        expect(find.byKey(const ValueKey('metas-dialogo')), findsOneWidget);
        expect(find.byKey(const ValueKey('abas-PETR4')), findsOneWidget);
        if (compras) {
          expect(
            find.widgetWithText(OutlinedButton, 'Criar meta de alvo e stop'),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('Ver gráfico abre o gráfico do ativo', (t) async {
      await _montar(t);
      await _direito(t, _linha('L1'));
      await _escolher(t, 'Ver gráfico');
      expect(find.byKey(const Key('grafico-dialogo')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('grafico-dialogo')),
          matching: find.textContaining('PETR4'),
        ),
        findsWidgets,
      );
    });

    testWidgets('Adicionar ao Radar grava e avisa', (t) async {
      final (s, _) = await _montar(t);
      await _direito(t, _linha('L2'));
      await _escolher(t, 'Adicionar ao Radar');
      expect(s.chamadas, contains('adicionarRadar(VALE3)'));
      expect(find.text('VALE3 adicionado ao Radar.'), findsOneWidget);
      // da próxima vez, já está
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await _direito(t, _linha('L2'));
      expect(_item('Já está no Radar'), findsOneWidget);
    });

    testWidgets('Copiar ticker copia e avisa', (t) async {
      final (_, p) = await _montar(t);
      await _direito(t, _linha('L1'));
      await _escolher(t, 'Copiar ticker');
      expect(p.copias, ['PETR4']);
      expect(find.text('PETR4 copiado'), findsOneWidget);
    });

    testWidgets('Copiar ticker com falha avisa e não diz "copiado"', (t) async {
      await _montar(t, plataforma: _PlataformaSemCopia());
      await _direito(t, _linha('L1'));
      await _escolher(t, 'Copiar ticker');
      expect(find.text('PETR4 copiado'), findsNothing);
      expect(find.text('Não foi possível copiar PETR4.'), findsOneWidget);
    });

    testWidgets('dois cliques direitos seguidos abrem um só menu', (t) async {
      await _montar(t);
      final centro = t.getCenter(_linha('L1'));
      for (var i = 0; i < 2; i++) {
        final g = await t.startGesture(centro, buttons: kSecondaryButton);
        await g.up();
      }
      await t.pumpAndSettle();
      expect(_item('Copiar ticker'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(_item('Copiar ticker'), findsNothing);
    });

    testWidgets('a linha some com o menu aberto: a ação segue na tela', (
      t,
    ) async {
      await _montar(t);
      await t.tap(find.text('Posição em 28/10/2026'));
      await t.pumpAndSettle();
      await _direito(t, find.byKey(const Key('ativo-PETR4')));
      // a lista troca (e a linha é descartada) com o menu aberto
      Provider.of<ControleApuracao>(
        t.element(find.byKey(const Key('lista-posicoes'))),
        listen: false,
      ).escolherModo(ModoLista.carteira);
      await t.pump();
      await _escolher(t, 'Trocar mês…');
      expect(find.text('Mês atual'), findsOneWidget);
    });

    testWidgets('Trocar mês… abre a grade de meses', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Trocar mês…');
      expect(find.text('Mês atual'), findsOneWidget);
    });

    testWidgets('a troca de lista mostra o destino e alterna', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Posição em 28/10/2026');
      expect(find.byKey(const Key('lista-posicoes')), findsOneWidget);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Carteira atual');
      expect(find.byKey(const Key('tabela-lotes')), findsOneWidget);
    });

    testWidgets('Meta de lucro… abre as metas', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Meta de lucro…');
      expect(find.byKey(const ValueKey('metas-dialogo')), findsOneWidget);
    });

    testWidgets('Fechar mês segue o fluxo do botão', (t) async {
      await _montar(t);
      await _direito(t, find.text('Visualizando'));
      await _escolher(t, 'Fechar mês 10/2026');
      expect(find.text('Fechar 10/2026'), findsOneWidget);
    });
  });
}
