import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/telas/amigos/tela_amigos.dart';
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
