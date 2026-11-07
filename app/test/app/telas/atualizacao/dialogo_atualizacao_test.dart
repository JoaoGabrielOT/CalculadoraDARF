import 'dart:async';

import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/atualizacao/dialogo_atualizacao.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../apoio/abrir_formulario.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

InfoAtualizacao _info({String notas = 'Correções.', String versao = '9.9.9'}) =>
    InfoAtualizacao(
      versao: versao,
      notas: notas,
      url: 'https://exemplo.com/a.exe',
      tamanho: 100,
      sha256: '',
    );

Future<void> _abrir(
  WidgetTester t,
  ServicosFalsos s,
  InfoAtualizacao info, {
  PlataformaFalsa? plataforma,
}) => abrirNoTeste<void>(
  t,
  s,
  (c) => oferecerAtualizacao(c, info),
  plataforma: plataforma,
);

Future<void> _atualizar(WidgetTester t) async {
  await t.tap(find.text('Atualizar'));
  await t.pumpAndSettle();
}

void main() {
  group('oferecerAtualizacao', () {
    testWidgets('mostra versões e notas', (t) async {
      await _abrir(t, ServicosFalsos(), _info());
      expect(find.text('Nova versão disponível'), findsOneWidget);
      expect(
        find.text(
          'A versão 9.9.9 está disponível. Você está usando a 2.0.0.'
          '\n\nNovidades:\nCorreções.',
        ),
        findsOneWidget,
      );
      expect(find.text('Depois'), findsOneWidget);
    });

    testWidgets('sem notas não leva "Novidades"', (t) async {
      await _abrir(t, ServicosFalsos(), _info(notas: ''));
      expect(
        find.text('A versão 9.9.9 está disponível. Você está usando a 2.0.0.'),
        findsOneWidget,
      );
    });

    testWidgets('notas cortadas em 600 com … no Windows', (t) async {
      await _abrir(t, ServicosFalsos(), _info(notas: 'x' * 700));
      expect(find.textContaining('${'x' * 600}…'), findsOneWidget);
      expect(find.textContaining('x' * 601), findsNothing);
    });

    testWidgets('notas cortadas em 500 com … no Android', (t) async {
      await _abrir(
        t,
        ServicosFalsos(),
        _info(notas: 'x' * 700),
        plataforma: PlataformaFalsa(windows: false),
      );
      expect(find.textContaining('${'x' * 500}…'), findsOneWidget);
      expect(find.textContaining('x' * 501), findsNothing);
    });

    testWidgets('o corte tira o espaço do fim antes do …', (t) async {
      await _abrir(
        t,
        ServicosFalsos(),
        _info(notas: '${'a' * 599} ${'b' * 50}'),
      );
      expect(find.textContaining('${'a' * 599}…'), findsOneWidget);
    });

    testWidgets('Depois fecha sem baixar', (t) async {
      final s = ServicosFalsos();
      await _abrir(t, s, _info());
      await t.tap(find.text('Depois'));
      await t.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsNothing);
      expect(s.chamadas.any((c) => c.startsWith('baixarAtualizacao')), isFalse);
    });
  });

  group('DialogoAtualizacao', () {
    testWidgets('progresso mostra MB com vírgula', (t) async {
      final s = ServicosFalsos()..baixarFn = (_) => Completer<String>().future;
      await _abrir(t, s, _info());
      await _atualizar(t);
      expect(find.text('Atualizando para a versão 9.9.9'), findsOneWidget);
      expect(find.text('Baixando…'), findsOneWidget);
      s.eventosFalsos.add(const EventoProgresso(1258291, 31982592));
      await t.pumpAndSettle(); // a entrega do evento é um microtask
      expect(find.text('Baixando… 1,2 de 30,5 MB'), findsOneWidget);
      final barra = t.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(barra.value, closeTo(1258291 / 31982592, 1e-9));
      // sem total conhecido a barra fica indeterminada
      s.eventosFalsos.add(const EventoProgresso(2621440, 0));
      await t.pump(); // a entrega do evento é um microtask
      await t.pump();
      expect(find.text('Baixando… 2,5 MB'), findsOneWidget);
      expect(
        t
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('Cancelar chama cancelarDownload e fecha', (t) async {
      final espera = Completer<String>();
      final s = ServicosFalsos()..baixarFn = (_) => espera.future;
      final p = PlataformaFalsa();
      await _abrir(t, s, _info(), plataforma: p);
      await _atualizar(t);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('cancelarDownload()'));
      expect(find.text('Atualizando para a versão 9.9.9'), findsNothing);
      // o download que termina depois do cancelamento não instala
      espera.complete('/tmp/x.exe');
      await t.pumpAndSettle();
      expect(p.instalacoes, isEmpty);
    });

    testWidgets('ao terminar chama instalarAtualizacao (Windows)', (t) async {
      final s = ServicosFalsos()..caminhoBaixado = r'C:\tmp\novo.exe';
      final p = PlataformaFalsa();
      await _abrir(t, s, _info(), plataforma: p);
      await _atualizar(t);
      expect(p.instalacoes, [r'C:\tmp\novo.exe']);
      expect(
        find.text('Instalando. O app será reaberto em alguns segundos…'),
        findsOneWidget,
      );
    });

    testWidgets('no Android abre o instalador e oferece Fechar', (t) async {
      final s = ServicosFalsos()..caminhoBaixado = '/tmp/novo.apk';
      final p = PlataformaFalsa(windows: false);
      await _abrir(t, s, _info(), plataforma: p);
      await _atualizar(t);
      expect(p.instalacoes, ['/tmp/novo.apk']);
      expect(find.text('Abrindo o instalador do Android…'), findsOneWidget);
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
      expect(find.text('Atualizando para a versão 9.9.9'), findsNothing);
    });

    testWidgets('erro mostra "Não foi possível atualizar: …"', (t) async {
      final s = ServicosFalsos()
        ..erros['baixarAtualizacao'] = ErroAtualizacao('Arquivo corrompido.');
      await _abrir(t, s, _info());
      await _atualizar(t);
      expect(
        find.text('Não foi possível atualizar: Arquivo corrompido.'),
        findsOneWidget,
      );
      expect(find.text('Cancelar'), findsNothing);
      await t.tap(find.text('Fechar'));
      await t.pumpAndSettle();
      expect(find.text('Atualizando para a versão 9.9.9'), findsNothing);
    });

    testWidgets('falha ao instalar nunca mostra "Exception:"', (t) async {
      final p = PlataformaFalsa()..falhaPlugin = Exception('sem permissão');
      await _abrir(t, ServicosFalsos(), _info(), plataforma: p);
      await _atualizar(t);
      expect(
        find.textContaining('Não foi possível atualizar: '),
        findsOneWidget,
      );
      expect(find.textContaining('Exception:'), findsNothing);
    });
  });
}
