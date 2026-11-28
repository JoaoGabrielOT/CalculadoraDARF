import 'dart:async';

import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/amigos/tela_amigos.dart';
import 'package:calculadoradarf/integracoes/google/compartilhamento.dart';
import 'package:calculadoradarf/integracoes/google/erros.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/servicos_falsos.dart';

const _pc = Size(1366, 900);
const _celular = Size(400, 850);

ServicosFalsos _servicos({List<Amigo> amigos = const []}) => ServicosFalsos()
  ..estadoConta = const EstadoConta(
    email: 'eu@gmail.com',
    linkPlanilha: 'https://docs.google.com/spreadsheets/d/x',
  )
  ..listaAmigos = [...amigos];

Future<void> _abrir(WidgetTester t, ServicosFalsos s, {Size tamanho = _pc}) =>
    abrirNoTeste<void>(t, s, abrirAmigos, tamanho: tamanho);

final _bia = Amigo(email: 'bia@gmail.com', desde: '2026-10-01');

String _status(WidgetTester t) =>
    t.widget<Text>(find.byKey(const Key('amigos-status'))).data ?? '';

String _statusRelatorios(WidgetTester t) {
  final f = find.byKey(const Key('amigos-relatorios-status'));
  return f.evaluate().isEmpty ? '' : t.widget<Text>(f).data ?? '';
}

const _textoPermitir =
    'Para compartilhar a pasta de relatórios automaticamente com seus amigos, '
    'entre de novo com o Google e permita o acesso ao Drive.';

void main() {
  for (final (nome, tamanho) in [('diálogo', _pc), ('celular', _celular)]) {
    group(nome, () {
      testWidgets('adicionar compartilha e lista', (t) async {
        final s = _servicos();
        await _abrir(t, s, tamanho: tamanho);
        expect(find.text('Nenhum amigo adicionado.'), findsOneWidget);
        await t.enterText(campo('amigos-email'), '  Bia@Gmail.com ');
        await t.tap(find.byKey(const Key('amigos-adicionar')));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('adicionarAmigo(bia@gmail.com)'));
        expect(_status(t), 'Planilha compartilhada com bia@gmail.com.');
        expect(find.text('bia@gmail.com'), findsOneWidget);
        expect(find.text('Adicionado em 28/10/2026'), findsOneWidget);
        expect(campoTexto(t, 'amigos-email').controller!.text, '');
        expect(find.text('Nenhum amigo adicionado.'), findsNothing);
      });

      testWidgets('erro mostra o texto', (t) async {
        final s = _servicos();
        s.erros['adicionarAmigo'] = ErroValidacao('E-mail inválido.');
        await _abrir(t, s, tamanho: tamanho);
        await t.enterText(campo('amigos-email'), 'xx');
        await t.tap(find.byKey(const Key('amigos-adicionar')));
        await t.pumpAndSettle();
        expect(_status(t), 'E-mail inválido.');
        expect(campoTexto(t, 'amigos-email').controller!.text, 'xx');
        s.erros['adicionarAmigo'] = Offline();
        await t.tap(find.byKey(const Key('amigos-adicionar')));
        await t.pumpAndSettle();
        expect(_status(t), 'Sem conexão com a internet.');
        // o botão volta a habilitar depois do erro
        final b = t.widget<FilledButton>(
          find.byKey(const Key('amigos-adicionar')),
        );
        expect(b.onPressed, isNotNull);
      });

      testWidgets('remover confirma com o texto do Python', (t) async {
        final s = _servicos(amigos: [_bia]);
        await _abrir(t, s, tamanho: tamanho);
        await t.tap(find.byKey(const Key('amigo-remover-bia@gmail.com')));
        await t.pumpAndSettle();
        expect(find.text('Remover amigo'), findsOneWidget);
        expect(
          find.text('bia@gmail.com deixará de ter acesso à sua planilha.'),
          findsOneWidget,
        );
        await t.tap(find.text('Cancelar'));
        await t.pumpAndSettle();
        expect(s.chamadas.any((c) => c.startsWith('removerAmigo')), isFalse);
        await t.tap(find.byKey(const Key('amigo-remover-bia@gmail.com')));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('removerAmigo(bia@gmail.com)'));
        expect(_status(t), 'Acesso de bia@gmail.com removido.');
        expect(find.text('Nenhum amigo adicionado.'), findsOneWidget);
      });

      testWidgets('erro ao remover mantém o amigo e mostra o texto', (t) async {
        final s = _servicos(amigos: [_bia]);
        s.erros['removerAmigo'] = ErroGoogle('O Google recusou.', 403);
        await _abrir(t, s, tamanho: tamanho);
        await t.tap(find.byKey(const Key('amigo-remover-bia@gmail.com')));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await t.pumpAndSettle();
        expect(_status(t), 'O Google recusou.');
        expect(find.text('bia@gmail.com'), findsOneWidget);
      });

      testWidgets('Ver troca a visão e fecha', (t) async {
        final s = _servicos(amigos: [_bia]);
        await _abrir(t, s, tamanho: tamanho);
        await t.tap(find.byKey(const Key('amigo-ver-bia@gmail.com')));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('carregarAmigo(bia@gmail.com)'));
        expect(find.byKey(const Key('amigos-email')), findsNothing);
        final estado = t
            .element(find.text('abrir', skipOffstage: false))
            .read<EstadoApp>();
        expect(estado.amigo, 'bia@gmail.com');
      });

      testWidgets('remover o amigo aberto volta para Meus dados', (t) async {
        final s = _servicos(amigos: [_bia]);
        await _abrir(t, s, tamanho: tamanho);
        final estado = t
            .element(find.text('abrir', skipOffstage: false))
            .read<EstadoApp>();
        await t.tap(find.byKey(const Key('amigo-ver-bia@gmail.com')));
        await t.pumpAndSettle();
        expect(estado.amigo, 'bia@gmail.com');
        await t.tap(find.text('abrir'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('amigo-remover-bia@gmail.com')));
        await t.pumpAndSettle();
        await t.tap(find.widgetWithText(FilledButton, 'Remover'));
        await t.pumpAndSettle();
        expect(estado.amigo, isNull);
      });
    });
  }

  group('pasta de relatórios', () {
    for (final (nome, tamanho) in [
      ('diálogo', _pc),
      ('celular 360', const Size(360, 800)),
    ]) {
      testWidgets('$nome: não dono, nada aparece nem é compartilhado', (
        t,
      ) async {
        final s = _servicos(amigos: [_bia]);
        await _abrir(t, s, tamanho: tamanho);
        expect(s.chamadas, contains('estadoCompartilhamento()'));
        expect(s.chamadas, isNot(contains('compartilharRelatorios()')));
        expect(find.text(_textoPermitir), findsNothing);
        expect(find.text('Permitir'), findsNothing);
        expect(_statusRelatorios(t), '');
      });

      testWidgets('$nome: dono sem escopo vê o aviso; Permitir compartilha', (
        t,
      ) async {
        final s = _servicos(amigos: [_bia])
          ..estadoCompartilhamentoResp = EstadoCompartilhamento.semEscopo
          ..estadoAposPermitir = EstadoCompartilhamento.pronto
          ..resultadosCompartilhamento.add(
            const ResultadoCompartilhamento(compartilhados: 1),
          );
        await _abrir(t, s, tamanho: tamanho);
        expect(find.text(_textoPermitir), findsOneWidget);
        expect(s.chamadas, isNot(contains('compartilharRelatorios()')));
        expect(t.takeException(), isNull);

        await t.tap(find.widgetWithText(FilledButton, 'Permitir'));
        await t.pumpAndSettle();
        expect(s.chamadas, contains('permitirCompartilhamento()'));
        expect(s.chamadas, contains('compartilharRelatorios()'));
        expect(find.text(_textoPermitir), findsNothing);
        expect(
          _statusRelatorios(t),
          'Pasta de relatórios compartilhada com 1 amigo(s)',
        );
      });
    }

    testWidgets('dono com escopo: ao abrir compartilha com quem falta', (
      t,
    ) async {
      final s = _servicos(amigos: [_bia])
        ..estadoCompartilhamentoResp = EstadoCompartilhamento.pronto
        ..resultadosCompartilhamento.add(
          const ResultadoCompartilhamento(
            compartilhados: 2,
            recusados: ['sem@conta.com'],
          ),
        );
      await _abrir(t, s);
      expect(s.chamadas, contains('compartilharRelatorios()'));
      expect(find.text(_textoPermitir), findsNothing);
      expect(
        _statusRelatorios(t),
        allOf(
          contains('Pasta de relatórios compartilhada com 2 amigo(s)'),
          contains('sem@conta.com'),
        ),
      );
    });

    testWidgets('ao abrir sem internet: silêncio', (t) async {
      final s = _servicos(amigos: [_bia])
        ..estadoCompartilhamentoResp = EstadoCompartilhamento.pronto
        ..resultadosCompartilhamento.add(
          const ResultadoCompartilhamento(erro: 'Sem conexão'),
        );
      await _abrir(t, s);
      expect(_statusRelatorios(t), '');
    });

    testWidgets('adicionar amigo compartilha a pasta e avisa', (t) async {
      final s = _servicos()
        ..estadoCompartilhamentoResp = EstadoCompartilhamento.pronto
        ..resultadosCompartilhamento.addAll([
          const ResultadoCompartilhamento(),
          const ResultadoCompartilhamento(compartilhados: 1),
        ]);
      await _abrir(t, s);
      await t.enterText(campo('amigos-email'), 'bia@gmail.com');
      await t.tap(find.byKey(const Key('amigos-adicionar')));
      await t.pumpAndSettle();
      expect(_status(t), 'Planilha compartilhada com bia@gmail.com.');
      expect(find.text('bia@gmail.com'), findsOneWidget);
      expect(
        _statusRelatorios(t),
        'Pasta de relatórios compartilhada com 1 amigo(s)',
      );
    });

    testWidgets('adicionar com falha (403): amigo salvo e aviso', (t) async {
      final s = _servicos()
        ..estadoCompartilhamentoResp = EstadoCompartilhamento.pronto
        ..resultadosCompartilhamento.addAll([
          const ResultadoCompartilhamento(),
          const ResultadoCompartilhamento(erro: 'O Google recusou.'),
        ]);
      await _abrir(t, s);
      await t.enterText(campo('amigos-email'), 'bia@gmail.com');
      await t.tap(find.byKey(const Key('amigos-adicionar')));
      await t.pumpAndSettle();
      expect(_status(t), 'Planilha compartilhada com bia@gmail.com.');
      expect(find.text('bia@gmail.com'), findsOneWidget);
      expect(
        _statusRelatorios(t),
        'Amigo adicionado, mas a pasta de relatórios não foi compartilhada: '
        'O Google recusou.',
      );
    });

    testWidgets('adicionar com 403 sem escopo volta ao aviso "Permitir"', (
      t,
    ) async {
      final s = _servicos()
        ..estadoCompartilhamentoResp = EstadoCompartilhamento.pronto
        ..resultadosCompartilhamento.addAll([
          const ResultadoCompartilhamento(),
          const ResultadoCompartilhamento(
            semEscopo: true,
            erro: 'Insufficient Permission',
          ),
        ]);
      await _abrir(t, s);
      expect(find.text(_textoPermitir), findsNothing);
      await t.enterText(campo('amigos-email'), 'bia@gmail.com');
      await t.tap(find.byKey(const Key('amigos-adicionar')));
      await t.pumpAndSettle();
      expect(find.text('bia@gmail.com'), findsOneWidget);
      expect(find.text(_textoPermitir), findsOneWidget);
      // só o aviso "Permitir", sem o motivo em inglês do Google
      expect(_statusRelatorios(t), '');
      expect(find.textContaining('Insufficient'), findsNothing);
    });

    testWidgets('não dono: falha do serviço ao adicionar não aparece', (
      t,
    ) async {
      final s = _servicos();
      await _abrir(t, s);
      s.erros['compartilharRelatorios'] = Offline();
      await t.enterText(campo('amigos-email'), 'bia@gmail.com');
      await t.tap(find.byKey(const Key('amigos-adicionar')));
      await t.pumpAndSettle();
      expect(_status(t), 'Planilha compartilhada com bia@gmail.com.');
      expect(_statusRelatorios(t), '');
    });

    testWidgets('não dono: adicionar não mostra nada da pasta', (t) async {
      final s = _servicos();
      await _abrir(t, s);
      await t.enterText(campo('amigos-email'), 'bia@gmail.com');
      await t.tap(find.byKey(const Key('amigos-adicionar')));
      await t.pumpAndSettle();
      expect(_status(t), 'Planilha compartilhada com bia@gmail.com.');
      expect(_statusRelatorios(t), '');
    });
  });

  group('"Ver" e a aba', () {
    Future<EstadoApp> verCom(WidgetTester t, Size tamanho, Aba aba) async {
      final s = _servicos(amigos: [_bia]);
      await abrirNoTeste<void>(t, s, abrirAmigos, tamanho: tamanho);
      final estado = t
          .element(find.text('abrir', skipOffstage: false))
          .read<EstadoApp>();
      estado.irPara(aba);
      await t.tap(find.byKey(const Key('amigo-ver-bia@gmail.com')));
      await t.pumpAndSettle();
      expect(estado.amigo, 'bia@gmail.com');
      return estado;
    }

    testWidgets('no celular, de Notícias, Relatórios ou Conta, vai para a '
        'Apuração', (t) async {
      for (final aba in [Aba.noticias, Aba.relatorios, Aba.conta]) {
        final estado = await verCom(t, _celular, aba);
        expect(estado.aba, Aba.apuracao);
      }
    });

    testWidgets('no celular, de Caixa, fica onde está', (t) async {
      final estado = await verCom(t, _celular, Aba.caixa);
      expect(estado.aba, Aba.caixa);
    });

    testWidgets('no PC não troca de aba', (t) async {
      for (final aba in [Aba.noticias, Aba.relatorios, Aba.conta]) {
        final estado = await verCom(t, _pc, aba);
        expect(estado.aba, aba);
      }
    });
  });

  testWidgets('fechar a janela durante o compartilhamento não quebra', (
    t,
  ) async {
    final espera = Completer<void>();
    final s = _servicos()..esperaAdicionarAmigo = espera.future;
    await _abrir(t, s);
    await t.enterText(campo('amigos-email'), 'bia@gmail.com');
    await t.tap(find.byKey(const Key('amigos-adicionar')));
    await t.pump();
    await t.tap(find.text('Fechar'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('amigos-email')), findsNothing);
    espera.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('sem conta mostra o aviso do Python', (t) async {
    final s = ServicosFalsos();
    await _abrir(t, s);
    expect(find.text('Amigos'), findsOneWidget);
    expect(
      find.text('Conecte sua conta Google para adicionar amigos.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('amigos-email')), findsNothing);
  });

  testWidgets('sem planilha mostra o aviso do Python', (t) async {
    final s = ServicosFalsos()
      ..estadoConta = const EstadoConta(email: 'eu@gmail.com');
    await _abrir(t, s);
    expect(
      find.text(
        'Aguarde a criação da sua planilha no Google Drive e tente novamente.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('amigos-email')), findsNothing);
  });
}
