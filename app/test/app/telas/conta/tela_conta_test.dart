import 'package:calculadoradarf/app/estado/estado_app.dart';
import 'package:calculadoradarf/app/servicos/api.dart';
import 'package:calculadoradarf/app/servicos/eventos.dart';
import 'package:calculadoradarf/app/telas/amigos/tela_amigos.dart';
import 'package:calculadoradarf/app/telas/casca.dart';
import 'package:calculadoradarf/app/telas/conta/tela_conta.dart';
import 'package:calculadoradarf/app/tema/temas.dart';
import 'package:calculadoradarf/app/tema/tema_visual.dart';
import 'package:calculadoradarf/integracoes/integracoes.dart';
import 'package:calculadoradarf/nucleo/nucleo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../apoio/montar.dart';
import '../../apoio/plataforma_falsa.dart';
import '../../apoio/servicos_falsos.dart';

// Altas, para os botões do fim da lista ficarem na tela.
const _pc = Size(1366, 2000);
const _celular = Size(400, 2400);

const _link = 'https://docs.google.com/spreadsheets/d/abc';

const _conectada = EstadoConta(
  email: 'eu@gmail.com',
  temCredencial: true,
  status: StatusSync.ok,
  linkPlanilha: _link,
);

EstadoApp _estado(WidgetTester t) =>
    Provider.of<EstadoApp>(t.element(find.byType(Casca)), listen: false);

Future<void> _abrirConta(
  WidgetTester t,
  ServicosFalsos s, {
  Size tamanho = _pc,
  PlataformaFalsa? plataforma,
}) async {
  await montarApp(t, servicos: s, plataforma: plataforma, tamanho: tamanho);
  _estado(t).irPara(Aba.conta);
  await t.pumpAndSettle();
}

ServicosFalsos _servicos([EstadoConta conta = const EstadoConta()]) =>
    ServicosFalsos()..estadoConta = conta;

Finder _botao(String texto) => find.ancestor(
  of: find.descendant(of: find.byType(TelaConta), matching: find.text(texto)),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _habilitado(WidgetTester t, String texto) =>
    t.widget<ButtonStyleButton>(_botao(texto)).onPressed != null;

Color _fundo(WidgetTester t) =>
    Theme.of(t.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;

void main() {
  group('Google sem conta', () {
    testWidgets('mostra o status e Conectar Google', (t) async {
      final s = _servicos(const EstadoConta(temCredencial: true));
      await _abrirConta(t, s, tamanho: _celular);
      expect(find.text('○ Google não conectado'), findsWidgets);
      expect(_habilitado(t, 'Conectar Google'), isTrue);
      expect(find.text('Cancelar login'), findsNothing);
      await t.tap(_botao('Conectar Google'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('conectar()'));
    });

    testWidgets('Conectar desabilitado com ocupado; Cancelar login durante '
        'o status login', (t) async {
      final s = _servicos(
        const EstadoConta(
          temCredencial: true,
          status: StatusSync.login,
          ocupado: true,
        ),
      );
      await _abrirConta(t, s, tamanho: _celular);
      expect(_habilitado(t, 'Conectar Google'), isFalse);
      expect(find.text('◌ Aguardando login no navegador…'), findsWidgets);
      await t.tap(_botao('Cancelar login'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('cancelarLogin()'));
      expect(s.chamadas, isNot(contains('conectar()')));
      // o login acabou: o botão volta e o cancelamento some
      s.eventosFalsos.add(const EventoConta(EstadoConta(temCredencial: true)));
      await t.pumpAndSettle();
      expect(_habilitado(t, 'Conectar Google'), isTrue);
      expect(find.text('Cancelar login'), findsNothing);
    });

    testWidgets('conectar sem credencial mostra o aviso do Python', (t) async {
      final s = _servicos();
      await _abrirConta(t, s);
      await t.tap(_botao('Conectar Google'));
      await t.pumpAndSettle();
      expect(find.text('Credencial não encontrada'), findsOneWidget);
      expect(
        find.text(
          'Coloque o arquivo credentials.json na mesma pasta do programa '
          'ou gere o .exe com ele na pasta.',
        ),
        findsOneWidget,
      );
      expect(s.chamadas, isNot(contains('conectar()')));
    });

    testWidgets('erro ao conectar vira aviso sem "Exception:"', (t) async {
      final s = _servicos(const EstadoConta(temCredencial: true))
        ..erros['conectar'] = Exception('Exception: caiu');
      await _abrirConta(t, s);
      await t.tap(_botao('Conectar Google'));
      await t.pumpAndSettle();
      expect(find.text('Login não concluído'), findsOneWidget);
      expect(find.textContaining('Exception:'), findsNothing);
    });
  });

  group('Google conectado', () {
    testWidgets('mostra e-mail, status e o último erro', (t) async {
      final s = _servicos(
        const EstadoConta(
          email: 'eu@gmail.com',
          temCredencial: true,
          status: StatusSync.erro,
          ultimoErro: 'Sem permissão.',
          linkPlanilha: _link,
        ),
      );
      await _abrirConta(t, s, tamanho: _celular);
      expect(find.text('eu@gmail.com'), findsOneWidget);
      expect(find.text('● Erro ao sincronizar'), findsWidgets);
      expect(find.text('Último erro: Sem permissão.'), findsOneWidget);
      expect(find.text('Conectar Google'), findsNothing);
    });

    testWidgets('Sincronizar agora chama o serviço', (t) async {
      final s = _servicos(_conectada);
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(_botao('Sincronizar agora'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('sincronizarAgora()'));
    });

    testWidgets('erro ao sincronizar vira aviso', (t) async {
      final s = _servicos(_conectada)..erros['sincronizarAgora'] = Offline();
      await _abrirConta(t, s);
      await t.tap(_botao('Sincronizar agora'));
      await t.pumpAndSettle();
      expect(find.text('Sem conexão com a internet.'), findsOneWidget);
    });

    testWidgets('Abrir planilha abre o link', (t) async {
      final p = PlataformaFalsa();
      final s = _servicos(_conectada);
      await _abrirConta(t, s, tamanho: _celular, plataforma: p);
      await t.tap(_botao('Abrir planilha'));
      await t.pumpAndSettle();
      expect(p.urlsAbertas, [Uri.parse(_link)]);
    });

    testWidgets('Abrir planilha desabilitado sem planilha', (t) async {
      final s = _servicos(
        const EstadoConta(email: 'eu@gmail.com', temCredencial: true),
      );
      await _abrirConta(t, s, tamanho: _celular);
      expect(_habilitado(t, 'Abrir planilha'), isFalse);
    });

    testWidgets("Sair confirma e volta a 'Conectar Google'", (t) async {
      final s = _servicos(_conectada);
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(_botao('Sair'));
      await t.pumpAndSettle();
      expect(find.text('Sair da conta'), findsOneWidget);
      expect(
        find.text('Os dados continuam salvos neste computador e na planilha.'),
        findsOneWidget,
      );
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(s.chamadas, isNot(contains('sair()')));
      await t.tap(_botao('Sair'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sair'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('sair()'));
      s.eventosFalsos.add(const EventoConta(EstadoConta(temCredencial: true)));
      await t.pumpAndSettle();
      expect(_botao('Conectar Google'), findsOneWidget);
      expect(find.text('eu@gmail.com'), findsNothing);
    });

    testWidgets('no Android a confirmação diz "neste aparelho"', (t) async {
      final s = _servicos(_conectada);
      await _abrirConta(
        t,
        s,
        tamanho: _celular,
        plataforma: PlataformaFalsa(windows: false),
      );
      await t.tap(_botao('Sair'));
      await t.pumpAndSettle();
      expect(
        find.text('Os dados continuam salvos neste aparelho e na planilha.'),
        findsOneWidget,
      );
    });
  });

  group('Amigos', () {
    testWidgets('no celular o bloco fica dentro da Conta', (t) async {
      final s = _servicos(_conectada);
      await _abrirConta(t, s, tamanho: _celular);
      expect(find.byType(TelaAmigos), findsOneWidget);
      expect(find.byKey(const Key('amigos-email')), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget); // só o da casca
    });

    testWidgets('"Ver" no bloco troca a visão e vai para a Apuração', (
      t,
    ) async {
      final s = _servicos(_conectada)
        ..listaAmigos = [Amigo(email: 'bia@gmail.com', desde: '2026-10-01')];
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(find.byKey(const Key('amigo-ver-bia@gmail.com')));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('carregarAmigo(bia@gmail.com)'));
      expect(_estado(t).amigo, 'bia@gmail.com');
      expect(_estado(t).aba, Aba.apuracao);
    });

    testWidgets('no PC a seção abre o diálogo e o bloco não aparece', (
      t,
    ) async {
      final s = _servicos(_conectada);
      await _abrirConta(t, s);
      expect(find.byType(TelaAmigos), findsNothing);
      await t.tap(find.byKey(const Key('conta-abrir-amigos')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('amigos-dialogo')), findsOneWidget);
    });

    testWidgets('sem conta a seção não aparece', (t) async {
      final s = _servicos(const EstadoConta(temCredencial: true));
      await _abrirConta(t, s, tamanho: _celular);
      expect(find.byType(TelaAmigos), findsNothing);
    });
  });

  group('Configurações', () {
    testWidgets('escolher Terminal aplica o tema na hora', (t) async {
      final s = _servicos();
      await _abrirConta(t, s, tamanho: _celular);
      final antes = _fundo(t);
      await t.tap(find.byKey(const Key('tema-terminal')));
      await t.pump();
      final terminal = temaDe(
        resolverTema(TemaVisual.terminal, Brightness.light),
      ).scaffoldBackgroundColor;
      expect(antes, isNot(terminal));
      expect(_fundo(t), terminal);
      await t.pumpAndSettle();
      expect(s.preferenciasSalvas!.tema, TemaVisual.terminal);
    });

    testWidgets('mostra os quatro temas, com o escolhido marcado', (t) async {
      final s = _servicos();
      await _abrirConta(t, s, tamanho: _celular);
      for (final r in ['Automático', 'Terminal', 'Claro', 'Moderno']) {
        expect(find.widgetWithText(ChoiceChip, r), findsOneWidget);
      }
      final claro = t.widget<ChoiceChip>(find.byKey(const Key('tema-claro')));
      expect(claro.selected, isTrue); // montarApp parte do tema Claro
      await t.tap(find.byKey(const Key('tema-moderno')));
      await t.pumpAndSettle();
      expect(
        t.widget<ChoiceChip>(find.byKey(const Key('tema-moderno'))).selected,
        isTrue,
      );
      expect(
        t.widget<ChoiceChip>(find.byKey(const Key('tema-claro'))).selected,
        isFalse,
      );
    });

    testWidgets('a chave de notícias começa ligada e grava ao desligar', (
      t,
    ) async {
      final s = _servicos();
      await _abrirConta(t, s, tamanho: _celular);
      final chave = find.byKey(const Key('conta-notificar'));
      expect(find.text('Notificar notícias relevantes'), findsOneWidget);
      expect(t.widget<Switch>(chave).value, isTrue);
      await t.tap(chave);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(chave).value, isFalse);
      expect(s.preferenciasSalvas!.notificarNoticias, isFalse);
    });
  });

  group('Sobre', () {
    testWidgets('mostra o nome e a versão', (t) async {
      await _abrirConta(t, _servicos(), tamanho: _celular);
      expect(find.text('Versão 2.3.0'), findsOneWidget);
    });

    testWidgets('sem nova versão avisa que já está na mais recente', (t) async {
      final s = _servicos();
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(_botao('Verificar atualização'));
      await t.pumpAndSettle();
      expect(
        find.text('Você já está na versão mais recente (2.3.0).'),
        findsOneWidget,
      );
    });

    testWidgets('erro avisa que não foi possível verificar', (t) async {
      final s = _servicos()..erros['verificarAtualizacao'] = Offline();
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(_botao('Verificar atualização'));
      await t.pumpAndSettle();
      expect(
        find.text('Não foi possível verificar atualizações.'),
        findsOneWidget,
      );
    });

    testWidgets('com nova versão oferece a atualização', (t) async {
      final s = _servicos()
        ..infoAtualizacao = const InfoAtualizacao(
          versao: '9.9.9',
          notas: 'Novo.',
          url: 'https://exemplo.com/a.exe',
          tamanho: 10,
          sha256: '',
        );
      await _abrirConta(t, s, tamanho: _celular);
      await t.tap(_botao('Verificar atualização'));
      await t.pumpAndSettle();
      expect(find.text('Nova versão disponível'), findsOneWidget);
      expect(
        find.text('Você já está na versão mais recente (2.3.0).'),
        findsNothing,
      );
    });
  });

  group('botão da conta no cabeçalho (PC)', () {
    Finder cabecalho(String texto) => find.descendant(
      of: find.byType(OutlinedButton),
      matching: find.text(texto),
    );

    testWidgets('sem credencial avisa', (t) async {
      final s = _servicos();
      await montarApp(t, servicos: s);
      await t.tap(cabecalho('Conectar Google'));
      await t.pumpAndSettle();
      expect(find.text('Credencial não encontrada'), findsOneWidget);
    });

    testWidgets('sem conta conecta', (t) async {
      final s = _servicos(const EstadoConta(temCredencial: true));
      await montarApp(t, servicos: s);
      await t.tap(cabecalho('Conectar Google'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('conectar()'));
    });

    testWidgets('desabilitado durante o login', (t) async {
      final s = _servicos(
        const EstadoConta(
          temCredencial: true,
          status: StatusSync.login,
          ocupado: true,
        ),
      );
      await montarApp(t, servicos: s);
      final botao = t.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Conectar Google'),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('conectada abre o menu do Windows', (t) async {
      final p = PlataformaFalsa();
      final s = _servicos(
        const EstadoConta(
          email: 'eu@gmail.com',
          temCredencial: true,
          status: StatusSync.erro,
          ultimoErro: 'Sem permissão.',
          linkPlanilha: _link,
        ),
      );
      await montarApp(t, servicos: s, plataforma: p);
      await t.tap(cabecalho('eu@gmail.com'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'Planilha "Calculadora DARF" no seu Google Drive.'
          '\n\nÚltimo erro: Sem permissão.',
        ),
        findsOneWidget,
      );
      await t.tap(find.text('Abrir planilha'));
      await t.pumpAndSettle();
      expect(p.urlsAbertas, [Uri.parse(_link)]);
      expect(find.text('Sem permissão.'), findsNothing);
    });

    testWidgets('o menu sincroniza e sai com confirmação', (t) async {
      final s = _servicos(_conectada);
      await montarApp(t, servicos: s);
      await t.tap(cabecalho('eu@gmail.com'));
      await t.pumpAndSettle();
      expect(
        find.text('Planilha "Calculadora DARF" no seu Google Drive.'),
        findsOneWidget,
      );
      await t.tap(find.text('Sincronizar agora'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('sincronizarAgora()'));
      await t.tap(cabecalho('eu@gmail.com'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sair da conta'));
      await t.pumpAndSettle();
      expect(
        find.text('Os dados continuam salvos neste computador e na planilha.'),
        findsOneWidget,
      );
      await t.tap(find.widgetWithText(FilledButton, 'Sair'));
      await t.pumpAndSettle();
      expect(s.chamadas, contains('sair()'));
    });
  });
}
